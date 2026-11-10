<p align="center">
  <img src="assets/Media-Share-Mapper.png" alt="Media Share Mapper icon" width="128">
</p>

# Media Share Mapper

Maps your NAS shares to drive letters on Windows and keeps them connected after every restart.

![Version](https://img.shields.io/badge/version-v1.00-blue) ![Platform](https://img.shields.io/badge/platform-Windows-0078D6) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE) ![Licence](https://img.shields.io/badge/licence-MIT-green)

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

**Exe:** download `Media Share Mapper v1.00.exe` from the [latest release](../../releases/latest), put it somewhere it can stay (the sign-in task runs it from there) and double-click it.

**Script:** clone or download the repo, then double-click **`Start Media Share Mapper.cmd`**. It runs the script with an execution-policy bypass for that run only; no Windows settings are changed. If you downloaded a zip and Windows blocks the files, right-click the zip, choose **Properties**, tick **Unblock**, then unzip it again.

### Build the exe

Builds use the standard build script, which reads `build.json`, runs PSScriptAnalyzer, compiles a console exe with [ps2exe](https://github.com/MScholtes/PS2EXE) and saves it to the project's `Builds\` folder (outside the repo) as `Media Share Mapper v<version>.exe`:

```powershell
E:\Created\_shared\Build-Tool.ps1 -Project "E:\Created\Home\Media-Share-Mapper"
```

Until the shared build script is in place, double-click `Build-Exe.cmd` in the repo folder instead. It checks the script for syntax errors, installs ps2exe for your user the first time and saves its output to `Build-Exe.log`. The version comes from `$AppVersion` at the top of `src\Media-Share-Mapper.ps1`, which matches the newest CHANGELOG entry.

## 🚀 Usage

Start it and pick from the menu. The first time, go through these in order:

1. **6 Edit settings** opens your settings file in Notepad (it's created from the example the first time). Put in your NAS name, drive letters and shares. See Configuration below.
2. **2 Save NAS sign-in** asks for the NAS user name and password and saves them in Windows Credential Manager. Use the NAS account, which may not be your Windows account. Run it again whenever the NAS password changes.
3. **1 Map drives now** maps them. **R** does the same but disconnects and remaps every drive, which is handy after a password change.
4. **3 Map drives when I sign in** creates the sign-in task. Windows asks for admin rights; the task itself runs as you, not as admin, because drives mapped by an admin process don't show in normal Explorer windows.

**5 Apply drive icons** sets the icons on their own (mapping does this too). **L** opens the logs folder and **A** shows the version and where your settings are.

### Command line

```powershell
.\src\Media-Share-Mapper.ps1 -Action Map            # map drives, then wait for Enter
.\src\Media-Share-Mapper.ps1 -Action Map -Force     # remap every drive
.\src\Media-Share-Mapper.ps1 -Action Map -Quiet     # no window output; what the sign-in task runs
```

`-Action` is one of `Menu` (the default), `Map`, `SaveCredential`, `InstallTask`, `RemoveTask`, `ApplyIcons`, `EditConfig` and `About`. Add `-NoPause` to close without waiting for Enter. The exe takes the same options. It exits with 0 when everything worked, 1 when a drive failed and 2 when the settings need fixing.

### Troubleshooting

- **A drive says FAILED**: the reason is shown next to it and saved in the logs folder. Error 1326 or 86 means the saved password is wrong (use option 2 again). Error 67 means the share name is wrong. Error 1219 means Windows is already connected to the NAS under another user name.
- **Drives map when I run it, but not at sign-in**: check the newest `Map_*.log` in the logs folder. If you moved or renamed the exe or script, or updated to a new version, run option 3 again so the task points at the right file.
- **"Running scripts is disabled"**: start it with `Start Media Share Mapper.cmd`, or use the exe.
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

A `config.local.json` next to the exe or script is used instead if there is one, for a portable copy. It's gitignored, so your NAS name and share paths stay on your PC. [`config.example.json`](config.example.json) shows the layout:

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
