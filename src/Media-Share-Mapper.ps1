#Requires -Version 5.1
<#
.SYNOPSIS
    Maps NAS shares to drive letters on Windows and keeps them connected.

.DESCRIPTION
    Media Share Mapper reads a list of shares and drive letters from
    config.local.json and maps each one, skipping drives that are already
    connected to the right share. It can also save the NAS sign-in to Windows
    Credential Manager, set itself up to run shortly after you sign in to
    Windows, and give the drives custom icons.

    Run it with no parameters for a menu.

.PARAMETER Action
    What to do. Menu (the default), Map, SaveCredential, InstallTask,
    RemoveTask, ApplyIcons, EditConfig or About.

.PARAMETER Quiet
    No menu, colours or pause at the end; results go to the log only. Used by
    the scheduled task.

.PARAMETER Force
    With -Action Map: disconnect and remap every drive, even ones that are
    already connected to the right share.

.PARAMETER NoPause
    Don't wait for Enter before closing.

.EXAMPLE
    .\Media-Share-Mapper.ps1
    Shows the menu.

.EXAMPLE
    .\Media-Share-Mapper.ps1 -Action Map -Force
    Remaps every drive in the settings file.

.NOTES
    Settings: %APPDATA%\Media Share Mapper\config.local.json (see
    config.example.json). Logs: %APPDATA%\Media Share Mapper\Logs.
    Copyright (c) 2026 Jason Rhodes. MIT licence.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Force',
    Justification = 'Script-level switch read inside Invoke-DriveMapping.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NoPause',
    Justification = 'Script-level switch read inside Wait-ForEnter.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TaskUser',
    Justification = 'Script-level parameter read inside Install-MapTask.')]
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Map', 'SaveCredential', 'InstallTask', 'RemoveTask', 'ApplyIcons', 'EditConfig', 'About')]
    [string]$Action = 'Menu',

    [switch]$Quiet,

    [switch]$Force,

    [switch]$NoPause,

    # Set when the menu restarts itself as Administrator to create the task, so the task
    # is still made for the account that asked for it.
    [string]$TaskUser
)

$AppName    = 'Media Share Mapper'
$AppVersion = '1.01'
$Copyright  = 'Copyright (c) 2026 Jason Rhodes'
$RepoUrl    = 'https://github.com/jason4bury/Media-Share-Mapper'
$TaskName   = 'Media Share Mapper'

$DataFolder = Join-Path $env:APPDATA $AppName
$LogFolder  = Join-Path $DataFolder 'Logs'
$ConfigName = 'config.local.json'

# ---------------------------------------------------------------------------
#  Where we are running from
# ---------------------------------------------------------------------------

# There's no exe from v1.01: this script is the app, in a release folder
# (Builds\Media Share Mapper v<version>\ or wherever the zip was unpacked) or in
# the repo's src\ folder.
$ScriptFile = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$AppFolder  = Split-Path -Parent $ScriptFile

# The sign-in task and the "run as admin" restart always use Windows PowerShell 5.1,
# whatever started this run, so the task keeps working if PowerShell 7 is removed.
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------------------------------------------------------------------------
#  Windows API calls
#  - CredWrite saves the NAS sign-in without the password ever going on a
#    command line (cmdkey /pass: would show it to every process on the PC).
#  - WNetAddConnection2 / WNetCancelConnection2 / WNetGetConnection map drives
#    and return real Windows error numbers (net.exe only ever exits with 2).
#  - SHChangeNotify tells Explorer to reload drive icons, so it doesn't need
#    restarting.
# ---------------------------------------------------------------------------

if (-not ('MediaShareMapper.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace MediaShareMapper
{
    public static class Native
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NETRESOURCE
        {
            public int dwScope;
            public int dwType;
            public int dwDisplayType;
            public int dwUsage;
            public string lpLocalName;
            public string lpRemoteName;
            public string lpComment;
            public string lpProvider;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL
        {
            public int Flags;
            public int Type;
            public string TargetName;
            public string Comment;
            public long LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
        private static extern int WNetAddConnection2(ref NETRESOURCE netResource, string password, string userName, int flags);

        [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
        private static extern int WNetCancelConnection2(string name, int flags, bool force);

        [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
        private static extern int WNetGetConnection(string localName, StringBuilder remoteName, ref int length);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref CREDENTIAL credential, int flags);

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);

        private const int RESOURCETYPE_DISK = 1;
        private const int CONNECT_UPDATE_PROFILE = 1;   // remember the drive (persistent)
        private const int CRED_TYPE_DOMAIN_PASSWORD = 2; // the type cmdkey /add makes
        private const int CRED_PERSIST_ENTERPRISE = 3;   // kept after sign-out, as cmdkey does

        // Maps localName (e.g. "M:") to remoteName using the signed-in user's saved
        // credentials. Returns 0 or a Windows error number.
        public static int MapDrive(string localName, string remoteName, bool persistent)
        {
            NETRESOURCE nr = new NETRESOURCE();
            nr.dwType = RESOURCETYPE_DISK;
            nr.lpLocalName = localName;
            nr.lpRemoteName = remoteName;
            return WNetAddConnection2(ref nr, null, null, persistent ? CONNECT_UPDATE_PROFILE : 0);
        }

        // Disconnects a drive letter and forgets it. Returns 0 or a Windows error number.
        public static int UnmapDrive(string localName)
        {
            return WNetCancelConnection2(localName, CONNECT_UPDATE_PROFILE, true);
        }

        // Returns 0 and the share in remoteName when the letter is a connected network
        // drive; 2250 when it isn't a network drive; 1201 when it is remembered but not
        // connected.
        public static int GetDriveShare(string localName, out string remoteName)
        {
            int length = 1024;
            StringBuilder sb = new StringBuilder(length);
            int result = WNetGetConnection(localName, sb, ref length);
            remoteName = sb.ToString();
            return result;
        }

        // Saves a Windows (domain-type) credential for target, like cmdkey /add.
        // The password is read from unmanaged memory that the caller zeroes and frees.
        public static int SaveCredential(string target, string userName, IntPtr password, int passwordChars)
        {
            CREDENTIAL cred = new CREDENTIAL();
            cred.Type = CRED_TYPE_DOMAIN_PASSWORD;
            cred.TargetName = target;
            cred.UserName = userName;
            cred.CredentialBlob = password;
            cred.CredentialBlobSize = passwordChars * 2;
            cred.Persist = CRED_PERSIST_ENTERPRISE;
            return CredWrite(ref cred, 0) ? 0 : Marshal.GetLastWin32Error();
        }

        // Tells Explorer that icons have changed.
        public static void RefreshIcons()
        {
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); // SHCNE_ASSOCCHANGED
        }
    }
}
'@
}

# ---------------------------------------------------------------------------
#  Output and logging
# ---------------------------------------------------------------------------

$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:PendingLine = ''

# Writes a line to the console (unless -Quiet) and keeps it for the log file.
function Write-Status {
    param(
        [string]$Message = '',
        [ConsoleColor]$Colour = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    # Text written with -NoNewline is held until the rest of the line arrives, so the
    # log has one line per drive, as the console does.
    $script:PendingLine += $Message
    if (-not $NoNewline) {
        $script:LogLines.Add($script:PendingLine)
        $script:PendingLine = ''
    }
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor $Colour -NoNewline:$NoNewline
    }
}

# Saves this run's output to Logs\, keeping the newest 20 log files.
function Save-RunLog {
    param([string]$Prefix = 'Map')
    try {
        if (-not (Test-Path -LiteralPath $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        }
        $file = Join-Path $LogFolder ('{0}_{1}.log' -f $Prefix, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $header = @(
            "$AppName v$AppVersion",
            "Run      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "User     : $env:USERDOMAIN\$env:USERNAME",
            "Started  : $(if ($Quiet) { 'quietly (scheduled task)' } else { 'interactively' })",
            ''
        )
        $lines = @($script:LogLines | ForEach-Object { $_ })
        if ($script:PendingLine) { $lines += $script:PendingLine }   # a line cut short by an error
        Set-Content -LiteralPath $file -Value ($header + $lines) -Encoding UTF8
        Get-ChildItem -LiteralPath $LogFolder -Filter "$Prefix`_*.log" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 20 |
            Remove-Item -Force -ErrorAction SilentlyContinue
        return $file
    }
    catch {
        Write-Verbose "Couldn't write the log: $($_.Exception.Message)"
        return $null
    }
}

function Write-Banner {
    param([string]$Title)
    if ($Quiet) { return }
    # Clear-Host throws when output is redirected (no real console).
    try { Clear-Host } catch { Write-Verbose $_.Exception.Message }
    Write-Host ''
    Write-Host '  ==========================================' -ForegroundColor Cyan
    Write-Host "     $AppName v$AppVersion" -ForegroundColor Cyan
    if ($Title) { Write-Host "     $Title" -ForegroundColor DarkCyan }
    Write-Host '  ==========================================' -ForegroundColor Cyan
    Write-Host ''
}

function Get-ErrorText {
    param([int]$Code)
    $text = (New-Object System.ComponentModel.Win32Exception $Code).Message
    $hint = switch ($Code) {
        53   { 'The NAS name could not be found. Is it switched on, and is NasHost right?' }
        67   { 'The share name is wrong, or the share no longer exists on the NAS.' }
        85   { 'The letter is already in use.' }
        86   { 'The saved password is wrong. Use "Save NAS sign-in" again.' }
        1219 { 'Windows is already connected to this NAS with a different user name. Disconnect the other drives or use the same account for all of them.' }
        1326 { 'The user name or password is wrong. Use "Save NAS sign-in" again.' }
        1244 { 'No sign-in is saved for the NAS. Use "Save NAS sign-in" first.' }
        default { $null }
    }
    if ($hint) { return "$text $hint" }
    return $text
}

# ---------------------------------------------------------------------------
#  Settings
# ---------------------------------------------------------------------------

# The starting settings file, used when there isn't one yet. Kept in step with
# config.example.json in the repo.
$ExampleConfig = @'
{
  "_readme": "Media Share Mapper settings, kept out of the repo. Drive is a letter. Share is a share name on NasHost, a folder inside one (music/live) or a full UNC path. Icon is optional: a file name in IconFolder or a full path to a .ico file. In paths, write each backslash twice.",

  "NasHost": "nas",
  "WaitForNasSeconds": 60,
  "IconFolder": "C:\\Icons\\Drives",

  "Drives": [
    { "Drive": "M", "Share": "music",  "Icon": "Music.ico" },
    { "Drive": "V", "Share": "video",  "Icon": "Movies.ico" },
    { "Drive": "P", "Share": "photo",  "Icon": "" }
  ],

  "OtherDriveIcons": [
    { "Drive": "C", "Icon": "Drives.ico" }
  ]
}
'@

# Settings live in %APPDATA%\Media Share Mapper. A copy next to the script is used
# instead if there is one there (handy for a portable copy).
function Get-ConfigPath {
    $beside = Join-Path $AppFolder $ConfigName
    if (Test-Path -LiteralPath $beside) { return $beside }
    return (Join-Path $DataFolder $ConfigName)
}

# Turns a Share value into a full \\server\share path.
function ConvertTo-UncPath {
    param([string]$NasHost, [string]$Share)
    $value = $Share.Trim().Replace('/', '\')
    if ($value.StartsWith('\\')) { return $value.TrimEnd('\') }
    return ('\\{0}\{1}' -f $NasHost, $value.Trim('\'))
}

# Reads and checks the settings file. Returns $null (after saying why) when it
# can't be used.
function Import-Config {
    $path = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Status "No settings file yet. Choose 'Edit settings' to create one:" Yellow
        Write-Status "  $path" Yellow
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Status "The settings file isn't valid JSON: $path" Red
        Write-Status "  $($_.Exception.Message)" Red
        Write-Status '  Tip: backslashes in paths must be doubled, e.g. "C:\\Icons".' DarkGray
        return $null
    }

    $problems = New-Object System.Collections.Generic.List[string]
    $nasHost = [string]$json.NasHost
    $wait = 60
    if ($null -ne $json.WaitForNasSeconds) {
        $wait = 0
        if (-not [int]::TryParse([string]$json.WaitForNasSeconds, [ref]$wait) -or $wait -lt 0 -or $wait -gt 600) {
            $problems.Add('WaitForNasSeconds must be a number from 0 to 600.')
        }
    }

    $iconFolder = [string]$json.IconFolder
    $resolveIcon = {
        param([string]$Icon)
        if ([string]::IsNullOrWhiteSpace($Icon)) { return $null }
        $Icon = [Environment]::ExpandEnvironmentVariables($Icon.Trim())
        if ([IO.Path]::IsPathRooted($Icon) -or [string]::IsNullOrWhiteSpace($iconFolder)) { return $Icon }
        # Not Join-Path: it fails when the drive isn't there (e.g. icons on a NAS drive).
        return [IO.Path]::Combine([Environment]::ExpandEnvironmentVariables($iconFolder.Trim()), $Icon)
    }

    $drives = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $index = 0
    foreach ($entry in @($json.Drives)) {
        $index++
        if ($null -eq $entry) { continue }
        $letter = ([string]$entry.Drive).Trim().TrimEnd(':', '\').ToUpperInvariant()
        $share = [string]$entry.Share
        if ($letter -notmatch '^[A-Z]$') {
            $problems.Add("Drives entry $index has Drive '$($entry.Drive)'; it must be one letter, e.g. ""M"".")
            continue
        }
        if ($seen.ContainsKey($letter)) {
            $problems.Add("Drive $letter is listed more than once.")
            continue
        }
        $seen[$letter] = $true
        if ([string]::IsNullOrWhiteSpace($share)) {
            $problems.Add("Drive $letter has no Share.")
            continue
        }
        if (-not $share.Trim().StartsWith('\\') -and [string]::IsNullOrWhiteSpace($nasHost)) {
            $problems.Add("Drive $letter uses a share name but NasHost is empty. Set NasHost or give a full \\server\share path.")
            continue
        }
        $drives.Add([PSCustomObject]@{
            Drive = $letter
            Share = ConvertTo-UncPath -NasHost $nasHost -Share $share
            Icon  = & $resolveIcon ([string]$entry.Icon)
        })
    }
    if ($drives.Count -eq 0 -and $problems.Count -eq 0) {
        $problems.Add('There are no drives in the Drives list.')
    }

    $otherIcons = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($json.OtherDriveIcons)) {
        if ($null -eq $entry) { continue }
        $letter = ([string]$entry.Drive).Trim().TrimEnd(':', '\').ToUpperInvariant()
        if ($letter -notmatch '^[A-Z]$') {
            $problems.Add("OtherDriveIcons has Drive '$($entry.Drive)'; it must be one letter.")
            continue
        }
        if ($seen.ContainsKey($letter)) {
            $problems.Add("Drive $letter is in both Drives and OtherDriveIcons; give its icon in Drives.")
            continue
        }
        $icon = & $resolveIcon ([string]$entry.Icon)
        if ($icon) { $otherIcons.Add([PSCustomObject]@{ Drive = $letter; Icon = $icon }) }
    }

    if ($problems.Count -gt 0) {
        Write-Status "Please fix the settings file: $path" Red
        foreach ($p in $problems) { Write-Status "  - $p" Red }
        return $null
    }

    # Every server the drives use, for saving sign-ins and checking the NAS is up.
    $servers = @($drives | ForEach-Object { ($_.Share.TrimStart('\') -split '\\')[0] } | Sort-Object -Unique)

    return [PSCustomObject]@{
        Path            = $path
        NasHost         = $nasHost
        WaitForNas      = $wait
        Drives          = $drives
        OtherDriveIcons = $otherIcons
        Servers         = $servers
    }
}

# Opens the settings file in Notepad, creating it from the example first if needed.
function Edit-Config {
    $path = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        $folder = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        Set-Content -LiteralPath $path -Value $ExampleConfig -Encoding UTF8
        Write-Status 'Created a new settings file from the example. Replace the example values with your own.' Green
    }
    Write-Status "Opening $path" Cyan
    Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$path`""
}

# ---------------------------------------------------------------------------
#  Mapping
# ---------------------------------------------------------------------------

# Waits until the server answers on the file-sharing port (445), for up to
# $Seconds. Returns $true if it answered.
function Wait-ForServer {
    param([string]$Server, [int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    $first = $true
    do {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $attempt = $client.BeginConnect($Server, 445, $null, $null)
            if ($attempt.AsyncWaitHandle.WaitOne(2000) -and $client.Connected) { return $true }
        }
        catch {
            Write-Verbose "No answer from ${Server}: $($_.Exception.Message)"   # name not found yet, or network not up
        }
        finally {
            $client.Close()
        }
        if ($first) {
            Write-Status "Waiting for $Server to answer (up to $Seconds seconds)..." Yellow
            $first = $false
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

# Disconnects a letter and checks it really is free, retrying because Windows
# doesn't always let go straight away. Returns $true when the letter is free.
function Clear-DriveLetter {
    param([string]$Drive)
    $name = "${Drive}:"
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        [void][MediaShareMapper.Native]::UnmapDrive($name)
        $remote = $null
        $state = [MediaShareMapper.Native]::GetDriveShare($name, [ref]$remote)
        if ($state -eq 2250) { return $true }   # not a network drive any more
        Start-Sleep -Milliseconds (300 * $attempt)
    }
    return $false
}

# Maps every drive in the settings. Returns the process exit code.
function Invoke-DriveMapping {
    $config = Import-Config
    if (-not $config) { return 2 }

    Write-Status "Settings: $($config.Path)" DarkGray
    Write-Status ''

    # At sign-in the network can take a while to come up.
    foreach ($server in $config.Servers) {
        if (-not (Wait-ForServer -Server $server -Seconds $config.WaitForNas)) {
            Write-Status "$server isn't answering. Drives on it will be tried anyway." Red
        }
    }

    $mapped = 0; $skipped = 0; $failed = 0
    $count = $config.Drives.Count; $current = 0

    foreach ($d in $config.Drives) {
        $current++
        if (-not $Quiet) {
            Write-Progress -Activity 'Mapping network drives' -Status "$current of $count" -PercentComplete (($current / $count) * 100)
        }
        $name = "$($d.Drive):"
        Write-Status ('{0}  {1,-40}' -f $name, $d.Share) -NoNewline

        # A local disk or USB stick using the letter can't be unmapped.
        $local = [IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -eq "$name\" -and $_.DriveType -ne 'Network' }
        if ($local) {
            $failed++
            Write-Status "  FAILED: $name is a $($local.DriveType.ToString().ToLower()) drive on this PC. Pick another letter." Red
            continue
        }

        # Already connected to the right share and readable? Leave it alone.
        $remote = $null
        $state = [MediaShareMapper.Native]::GetDriveShare($name, [ref]$remote)
        if (-not $Force -and $state -eq 0 -and $remote -eq $d.Share -and [IO.Directory]::Exists("$name\")) {
            $skipped++
            Write-Status '  already connected' Green
            continue
        }

        if ($state -ne 2250 -and -not (Clear-DriveLetter -Drive $d.Drive)) {
            Write-Status "  (couldn't confirm $name was released) " DarkYellow -NoNewline
        }

        $result = -1
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $result = [MediaShareMapper.Native]::MapDrive($name, $d.Share, $true)
            if ($result -ne 85) { break }
            # 85: the letter is still held. Let go of it again and retry.
            [void](Clear-DriveLetter -Drive $d.Drive)
            Start-Sleep -Milliseconds 750
        }

        if ($result -eq 0) {
            $mapped++
            Write-Status '  mapped' Green
        }
        else {
            $failed++
            Write-Status "  FAILED ($result): $(Get-ErrorText $result)" Red
        }
    }
    if (-not $Quiet) { Write-Progress -Activity 'Mapping network drives' -Completed }

    Write-Status ''
    Write-Status "Mapped: $mapped   Already connected: $skipped   Failed: $failed" $(if ($failed) { 'Red' } else { 'Green' })

    # Icons are per-user settings, so this works without admin rights. Nothing is
    # written (and Explorer isn't disturbed) unless an icon actually changed.
    if (@($config.Drives | Where-Object Icon).Count -gt 0 -or $config.OtherDriveIcons.Count -gt 0) {
        Write-Status ''
        [void](Set-DriveIcon -Config $config)
    }

    if ($failed -gt 0 -or $Quiet) {
        $log = Save-RunLog -Prefix 'Map'
        if ($log -and $failed -gt 0) {
            Write-Status ''
            Write-Status "Log saved to $log" Yellow
        }
    }
    if ($failed -gt 0) { return 1 }
    return 0
}

# ---------------------------------------------------------------------------
#  Drive icons
# ---------------------------------------------------------------------------

# Sets HKCU\...\Explorer\DriveIcons\<letter>\DefaultIcon for every drive with an
# icon. Returns the number of icons changed.
function Set-DriveIcon {
    param($Config)
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons'
    # Pipe the lists rather than @($list): Windows PowerShell 5.1 throws "Argument
    # types do not match" on @() around a List[object] property.
    $wanted = @($Config.Drives | Where-Object Icon) + @($Config.OtherDriveIcons | ForEach-Object { $_ })
    $changed = 0
    foreach ($item in $wanted) {
        if (-not (Test-Path -LiteralPath $item.Icon)) {
            Write-Status "Icon for $($item.Drive): not found: $($item.Icon)" DarkYellow
            continue
        }
        $key = Join-Path $root "$($item.Drive)\DefaultIcon"
        $value = '"{0}"' -f $item.Icon
        $current = $null
        if (Test-Path -LiteralPath $key) {
            $current = (Get-Item -LiteralPath $key).GetValue('')
        }
        if ($current -eq $value) { continue }
        try {
            if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
            Set-Item -LiteralPath $key -Value $value
            $changed++
        }
        catch {
            Write-Status "Couldn't set the icon for $($item.Drive): $($_.Exception.Message)" Red
        }
    }
    if ($changed -gt 0) {
        [MediaShareMapper.Native]::RefreshIcons()
        Write-Status "Drive icons updated: $changed. If Explorer still shows the old ones, close and reopen it." Green
    }
    else {
        Write-Status 'Drive icons are up to date.' DarkGray
    }
    return $changed
}

function Invoke-DriveIconUpdate {
    $config = Import-Config
    if (-not $config) { return 2 }
    [void](Set-DriveIcon -Config $config)
    return 0
}

# ---------------------------------------------------------------------------
#  NAS sign-in
# ---------------------------------------------------------------------------

# Asks for the NAS user name and password and saves them in Windows Credential
# Manager for each server in the settings. The password stays in a SecureString
# and goes to Windows through zeroed unmanaged memory, never a command line.
function Save-NasCredential {
    $config = Import-Config
    if (-not $config) { return 2 }
    if ($Quiet) {
        Write-Status 'Saving the NAS sign-in needs you at the keyboard; run it without -Quiet.' Red
        return 2
    }

    $servers = $config.Servers
    Write-Status "This saves your NAS user name and password in Windows Credential Manager for: $($servers -join ', ')"
    Write-Status 'Use the NAS account, not your Windows account if they differ.' DarkGray
    Write-Status ''

    $userName = Read-Host 'NAS user name'
    if ([string]::IsNullOrWhiteSpace($userName)) {
        Write-Status 'Cancelled - nothing saved.' Yellow
        return 1
    }
    $password = Read-Host 'NAS password' -AsSecureString
    if ($password.Length -eq 0) {
        Write-Status 'Cancelled - nothing saved.' Yellow
        return 1
    }

    $failed = 0
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($password)
        foreach ($server in $servers) {
            $result = [MediaShareMapper.Native]::SaveCredential($server, $userName.Trim(), $pointer, $password.Length)
            if ($result -eq 0) {
                Write-Status "Saved the sign-in for $server." Green
            }
            else {
                $failed++
                Write-Status "Couldn't save the sign-in for ${server}: $(Get-ErrorText $result)" Red
            }
        }
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($pointer) }
        $password.Dispose()
    }

    if ($failed -eq 0) {
        Write-Status ''
        Write-Status 'Done. Map the drives next. If a drive is already connected with the old password, choose Map with "remap all".' DarkGray
        return 0
    }
    return 1
}

# ---------------------------------------------------------------------------
#  Run at sign-in
# ---------------------------------------------------------------------------

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Registers a scheduled task that maps the drives 30 seconds after the user signs
# in. It runs NOT elevated on purpose: drives mapped from an elevated process
# belong to a separate session and don't show in normal Explorer windows.
function Install-MapTask {
    $user = if ($TaskUser) { $TaskUser } else { "$env:USERDOMAIN\$env:USERNAME" }

    if (-not (Test-IsAdmin)) {
        if ($Quiet) {
            Write-Status 'Creating the sign-in task needs Administrator rights.' Red
            return 1
        }
        Write-Status 'Creating the sign-in task needs Administrator rights. Windows will ask for permission.' Yellow
        $taskArgs = "-Action InstallTask -TaskUser `"$user`""
        try {
            $p = Start-Process -FilePath $PowerShellExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptFile`" $taskArgs" -Verb RunAs -Wait -PassThru
            if ($p.ExitCode -eq 0) { Write-Status 'The sign-in task was created.' Green }
            else { Write-Status 'The sign-in task was not created; see the other window for why.' Red }
            return $p.ExitCode
        }
        catch {
            Write-Status 'Cancelled - the task was not created.' Yellow
            return 1
        }
    }

    $action = New-ScheduledTaskAction -Execute $PowerShellExe `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptFile`" -Action Map -Quiet"

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $trigger.Delay = 'PT30S'

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

    try {
        # Older versions made a task called "Map Media Network Drives"; replace it.
        foreach ($old in @($TaskName, 'Map Media Network Drives')) {
            Unregister-ScheduledTask -TaskName $old -Confirm:$false -ErrorAction SilentlyContinue
        }
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Principal $principal -Description "Maps your NAS drives 30 seconds after you sign in ($AppName)." -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Status "Couldn't create the task: $($_.Exception.Message)" Red
        return 1
    }

    Write-Status "Created the '$TaskName' task for $user." Green
    Write-Status 'It maps the drives quietly 30 seconds after you sign in. Logs go to:' Green
    Write-Status "  $LogFolder" Green
    Write-Status 'The task runs this copy of the script:' DarkGray
    Write-Status "  $ScriptFile" DarkGray
    Write-Status 'After moving it or updating to a new version, choose this option again from the new copy.' DarkGray
    return 0
}

# Returns the script (or exe) the sign-in task runs, or $null when there's no task or it
# can't be read. Reading it needs no admin rights for a task made for this account.
function Get-MapTaskTarget {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    }
    catch {
        return $null
    }
    $taskAction = @($task.Actions)[0]
    if (-not $taskAction) { return $null }
    if ([string]$taskAction.Arguments -match '-File\s+"([^"]+)"') { return $Matches[1] }
    return ([string]$taskAction.Execute).Trim('"')   # v1.00's exe
}

# A note for the menu when the sign-in task runs a different copy (an older version, or
# one that has been moved or deleted). Worked out once per run; option 3 or 4 clears it.
$script:TaskNote = $null
$script:TaskChecked = $false
function Get-MapTaskNote {
    if (-not $script:TaskChecked) {
        $script:TaskChecked = $true
        $target = Get-MapTaskTarget
        if ($target -and $target -ne $ScriptFile) {
            $script:TaskNote = if (Test-Path -LiteralPath $target) {
                "The sign-in task runs another copy: $target"
            }
            else {
                "The sign-in task runs a file that's no longer there: $target"
            }
        }
    }
    return $script:TaskNote
}

function Uninstall-MapTask {
    $found = $false
    foreach ($name in @($TaskName, 'Map Media Network Drives')) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            $found = $true
            try {
                Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
                Write-Status "Removed the '$name' task." Green
            }
            catch {
                Write-Status "Couldn't remove '$name' (it may need Administrator rights): $($_.Exception.Message)" Red
                return 1
            }
        }
    }
    if (-not $found) { Write-Status 'There is no sign-in task to remove.' DarkGray }
    return 0
}

# ---------------------------------------------------------------------------
#  About and menu
# ---------------------------------------------------------------------------

function Show-About {
    Write-Status "$AppName v$AppVersion"
    Write-Status 'Maps NAS shares to drive letters and keeps them connected.'
    Write-Status ''
    Write-Status $Copyright
    Write-Status 'MIT licence'
    Write-Status $RepoUrl
    Write-Status ''
    Write-Status "Script   : $ScriptFile"
    Write-Status "Settings : $(Get-ConfigPath)"
    Write-Status "Logs     : $LogFolder"
    return 0
}

function Wait-ForEnter {
    if ($Quiet -or $NoPause) { return }
    Write-Host ''
    [void](Read-Host 'Press Enter to continue')
}

function Show-Menu {
    while ($true) {
        Write-Banner
        $configPath = Get-ConfigPath
        if (-not (Test-Path -LiteralPath $configPath)) {
            Write-Host '  First time? Start with 6 to fill in your settings, then 2, then 1.' -ForegroundColor Yellow
            Write-Host ''
        }
        $taskNote = Get-MapTaskNote
        if ($taskNote) {
            Write-Host "  $taskNote" -ForegroundColor Yellow
            Write-Host '  Choose 3 to point it at this version.' -ForegroundColor Yellow
            Write-Host ''
        }
        Write-Host '  1  Map drives now'
        Write-Host '  R  Map drives now, remapping every drive'
        Write-Host '  2  Save NAS sign-in'
        Write-Host '  3  Map drives when I sign in to Windows'
        Write-Host '  4  Stop mapping drives when I sign in'
        Write-Host '  5  Apply drive icons'
        Write-Host '  6  Edit settings'
        Write-Host '  L  Open the logs folder'
        Write-Host '  A  About'
        Write-Host '  Q  Quit'
        Write-Host ''
        $choice = (Read-Host '  Choose').Trim().ToUpperInvariant()

        $script:LogLines.Clear()
        switch ($choice) {
            '1' { Write-Banner 'Map drives'; [void](Invoke-DriveMapping); Wait-ForEnter }
            'R' { Write-Banner 'Remap every drive'; $script:Force = $true; [void](Invoke-DriveMapping); $script:Force = $false; Wait-ForEnter }
            '2' { Write-Banner 'Save NAS sign-in'; [void](Save-NasCredential); Wait-ForEnter }
            '3' { Write-Banner 'Map drives at sign-in'; [void](Install-MapTask); $script:TaskChecked = $false; $script:TaskNote = $null; Wait-ForEnter }
            '4' { Write-Banner 'Stop mapping at sign-in'; [void](Uninstall-MapTask); $script:TaskChecked = $false; $script:TaskNote = $null; Wait-ForEnter }
            '5' { Write-Banner 'Drive icons'; [void](Invoke-DriveIconUpdate); Wait-ForEnter }
            '6' { Edit-Config; Start-Sleep -Seconds 1 }
            'L' {
                if (-not (Test-Path -LiteralPath $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
                Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$LogFolder`""
            }
            'A' { Write-Banner 'About'; [void](Show-About); Wait-ForEnter }
            'Q' { return 0 }
            ''  { return 0 }
        }
    }
}

# ---------------------------------------------------------------------------
#  Start
# ---------------------------------------------------------------------------

if (-not $Quiet) {
    try { $Host.UI.RawUI.WindowTitle = "$AppName v$AppVersion" } catch { Write-Verbose $_.Exception.Message }
}

$exitCode = 0
try {
    switch ($Action) {
        'Menu' {
            if ($Quiet) {
                Write-Status '-Quiet needs an -Action, e.g. -Action Map -Quiet.' Red
                $exitCode = 2
            }
            else {
                $exitCode = Show-Menu
            }
        }
        'Map'            { Write-Banner 'Map drives'; $exitCode = Invoke-DriveMapping; Wait-ForEnter }
        'SaveCredential' { Write-Banner 'Save NAS sign-in'; $exitCode = Save-NasCredential; Wait-ForEnter }
        'InstallTask'    { Write-Banner 'Map drives at sign-in'; $exitCode = Install-MapTask; Wait-ForEnter }
        'RemoveTask'     { Write-Banner 'Stop mapping at sign-in'; $exitCode = Uninstall-MapTask; Wait-ForEnter }
        'ApplyIcons'     { Write-Banner 'Drive icons'; $exitCode = Invoke-DriveIconUpdate; Wait-ForEnter }
        'EditConfig'     { Edit-Config }
        'About'          { Write-Banner 'About'; $exitCode = Show-About; Wait-ForEnter }
    }
}
catch {
    Write-Status "Something went wrong: $($_.Exception.Message)" Red
    [void](Save-RunLog -Prefix 'Error')
    Wait-ForEnter
    $exitCode = 3
}

exit $exitCode
