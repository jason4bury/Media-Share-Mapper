<p align="center">
  <img src="assets/Media-Share-Mapper.png" alt="Media Share Mapper icon" width="128">
</p>

# Media Share Mapper

Maps your NAS shares to drive letters on Windows and keeps them connected after every restart.

![Version](https://img.shields.io/badge/version-v1.01-blue) ![Platform](https://img.shields.io/badge/platform-Windows-0078D6) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE) ![Licence](https://img.shields.io/badge/licence-MIT-green)

## ✨ Features

Windows' own "reconnect at sign-in" for network drives is unreliable with a home NAS: if the network or the saved password isn't ready in time, the drive just doesn't appear. Media Share Mapper fixes that by mapping the drives itself, shortly after you sign in.

- **Maps every drive in one go** from a list of drive letters and shares, and leaves drives that are already connected to the right share alone
- **Waits for the NAS** to answer before mapping (up to a minute by default), so a slow network at start-up doesn't leave you with missing drives
- **Retries** when Windows hasn't let go of a drive letter yet, and says plainly why a drive failed: wrong password, share not found, letter used by a USB stick and so on
- **Saves your NAS sign-in** in Windows Credential Manager, so no password is kept in a file or typed on a command line
- **Maps the drives when you sign in** with a scheduled task that runs quietly 30 seconds after sign-in, without admin rights
- **Custom drive icons** for the mapped drives (and your local drives if you like), applied without restarting Explorer
- A simple menu, or command-line options for scripts

## 📋 Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in, nothing to install)
- A NAS or other SMB file server (tested with Synology) and an account on it
- Administrator rights once, to create the sign-in task (Windows asks for them)

## 📦 Installation

1. Download `Media-Share-Mapper-v1.01.zip` from the [latest release](../../releases/latest) and unzip it somewhere it can stay, because the sign-in task runs the script from there.
2. Double-click **Media Share Mapper.cmd** in the unzipped folder. It makes a **Media Share Mapper** shortcut there and in the Start menu, and opens the menu in a console window. From then on, use the shortcut, the Start menu or a pinned taskbar button.

Nothing is installed and no Windows settings are changed. The shortcut runs the script with PowerShell's execution policy bypassed for that run only.

**From the repo:** clone it and double-click **Start Media Share Mapper.cmd**, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Media-Share-Mapper.ps1
```

**Updating:** unzip the new version, start it, and choose **3 Map drives when I sign in** again so the sign-in task runs the new copy. The menu reminds you while the task still points at an older copy. Your settings, sign-in and icons carry over.

### Why no exe

Home tools used to ship as PS2EXE exes, and antivirus programs (ESET among them) kept flagging those exes as generic trojans by mistake. A plain script and a shortcut give the same one-click start without the false alarms, and you can read exactly what runs. Up to v1.00 this tool was `Media Share Mapper v1.00.exe`; from v1.01 it's the script release above.

### Build a release

Double-click **Build.cmd** in the repo folder. It reads `build.json`, checks every script for syntax errors and that `$AppVersion` matches the newest `CHANGELOG.md` entry, runs PSScriptAnalyzer if it's installed, copies the release files into `..\Builds\Media Share Mapper v<version>\`, zips that folder for the GitHub release, refreshes `..\Builds\Media Share Mapper.lnk` and scans the result with ESET's command-line scanner if it's installed. Everything it shows is saved to `Build.log`.

## 🚀 Usage

Start it (the shortcut, the Start menu, or **Media Share Mapper.cmd**) and pick from the menu. The first time, go through these in order:

1. **6 Edit settings** opens your settings file in Notepad (it's created from the example the first time). Put in your NAS name, drive letters and shares. See Configuration below.
2. **2 Save NAS sign-in** asks for the NAS user name and password and saves them in Windows Credential Manager. Use the NAS account, which may not be your Windows account. Run it again whenever the NAS password changes.
3. **1 Map drives now** maps them. **R** does the same but disconnects and remaps every drive, which is handy after a password change.
4. **3 Map drives when I sign in** creates the sign-in task. Windows asks for admin rights; the task itself runs as you, not as admin, because drives mapped by an admin process don't show in normal Explorer windows.

**5 Apply drive icons** sets the icons on their own (mapping does this too). **L** opens the logs folder and **A** shows the version and where the script, your settings and the logs are.

### Command line

```powershell
.\src\Media-Share-Mapper.ps1 -Action Map            # map drives, then wait for Enter
.\src\Media-Share-Mapper.ps1 -Action Map -Force     # remap every drive
.\src\Media-Share-Mapper.ps1 -Action Map -Quiet     # no window output; what the sign-in task runs
```

`-Action` is one of `Menu` (the default), `Map`, `SaveCredential`, `InstallTask`, `RemoveTask`, `ApplyIcons`, `EditConfig` and `About`. Add `-NoPause` to close without waiting for Enter. **Media Share Mapper.cmd** in a release folder takes the same options, e.g. `"Media Share Mapper.cmd" -Action Map -Force`. It exits with 0 when everything worked, 1 when a drive failed and 2 when the settings need fixing.

### Troubleshooting

- **A drive says FAILED**: the reason is shown next to it and saved in the logs folder. Error 1326 or 86 means the saved password is wrong (use option 2 again). Error 67 means the share name is wrong. Error 1219 means Windows is already connected to the NAS under another user name.
- **Drives map when I run it, but not at sign-in**: check the newest `Map_*.log` in the logs folder. If you moved the script or updated to a new version, run option 3 again from the copy you use now, so the task points at the right file. The menu shows a yellow note while the task runs a different copy.
- **"Running scripts is disabled"**: start it with **Media Share Mapper.cmd** or its shortcut, which bypass the execution policy for that run only.
- **Windows blocks the files** from a downloaded zip: **Media Share Mapper.cmd** unblocks the tool's own files when it makes the shortcut. If Windows won't run the .cmd itself, right-click the zip, choose **Properties**, tick **Unblock**, then unzip it again.
- **Icons haven't changed**: close and reopen Explorer windows. If they still don't change, sign out and back in.

## ⚙️ Configuration

Your settings and logs live in:

```
%APPDATA%\Media Share Mapper\
```

| File or folder | What it holds |
| --- | --- |
| `config.local.json` | your NAS name, drive letters, shares and icons |
| `Logs\` | a log for every sign-in run and every run where a drive failed (newest 20 kept) |

A `config.local.json` next to the script is used instead if there is one, for a portable copy. It's gitignored, so your NAS name and share paths stay on your PC. [`config.example.json`](config.example.json) shows the layout:

| Setting | What it does |
| --- | --- |
| `NasHost` | the NAS's network name, e.g. `nas` or `192.168.1.20` |
| `WaitForNasSeconds` | how long to wait for the NAS to answer before mapping (0 to 600, default 60) |
| `IconFolder` | folder holding your `.ico` files, so icons can be given by file name |
| `Drives` | one entry per drive: `Drive` (a letter), `Share` (a share on `NasHost`, a folder inside one such as `music\\live`, or a full `\\\\server\\share` path) and an optional `Icon` |
| `OtherDriveIcons` | optional icons for drives that aren't mapped, such as `C` or a USB drive: `Drive` and `Icon` |

In JSON every backslash is written twice, e.g. `"C:\\Icons\\Drives"`.

The saved NAS sign-in is in Windows Credential Manager (**Control Panel > Credential Manager > Windows Credentials**), under the NAS name. Drive icons are per-user settings in `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons`.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md). History from before the v1.00 renumbering is in [docs/HISTORY-before-1.00.md](docs/HISTORY-before-1.00.md).

## 📄 Licence

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Jason Rhodes.
