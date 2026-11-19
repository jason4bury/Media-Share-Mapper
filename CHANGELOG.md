# Changelog

All notable changes to Media Share Mapper are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions in the form
`v<major>.<two-digit minor>`, matching the release folder names. History from before the v1.00
renumbering is in [docs/HISTORY-before-1.00.md](docs/HISTORY-before-1.00.md).

## [Unreleased]

## [1.02] - 2026-11-19

### Added
- **Help.** **H** in the menu (or `-Action Help`) shows how it works: the first-time steps, what each
  menu option does, the settings, and what to do when a drive fails or the icons don't change.
- About notes what's new in 1.02.

## [1.01] - 2026-11-16

### Changed
- **No exe any more.** Antivirus programs (ESET among them) kept flagging the PS2EXE exe as a
  generic trojan by mistake, so the release is now the script itself: download
  `Media-Share-Mapper-v1.01.zip`, unzip it and double-click **Media Share Mapper.cmd**. It makes
  a shortcut there and in the Start menu and opens the menu in a console window. Options given
  to the .cmd go straight to the script. Settings, logs, the saved sign-in and icons are
  unchanged.
- The sign-in task runs the script with Windows PowerShell 5.1, hidden, from wherever you
  chose option 3. After updating, choose option 3 again from the new copy.
- `Build.cmd` replaces `Build-Exe.cmd`: it makes the release folder, its zip and
  `Builds\Media Share Mapper.lnk`, and ESET-scans them.
- About (option A) also shows which script is running.

### Added
- The menu shows a yellow note when the sign-in task runs a different copy (an older version,
  or one that has been moved or deleted), such as the v1.00 exe.

### Removed
- The exe-only code: finding its own folder from the exe and hiding the exe's console window
  at sign-in.

## [1.00] - 2026-11-07

First release under the house-style version numbers. The repo was previously called `shares`.

### Added
- One script, `src\Media-Share-Mapper.ps1`, with a menu: map drives, remap every drive, save
  the NAS sign-in, create or remove the sign-in task, apply drive icons, edit settings, open
  the logs folder and About. Each one is also a command-line `-Action`, with `-Quiet`,
  `-Force` and `-NoPause`.
- Settings file `config.local.json` in `%APPDATA%\Media Share Mapper\` (gitignored, with
  `config.example.json` to copy). It holds the NAS name, the drives and the icons, so none of
  them are in the code. It's checked when it's read, with a clear message for each problem.
- Waits for the NAS to answer (up to `WaitForNasSeconds`, default 60) before mapping.
- Drive icons for local drives (`OtherDriveIcons`) as well as mapped ones.
- `Start Media Share Mapper.cmd`, `Build-Exe.cmd` and `build.json` to build
  `Media Share Mapper v1.00.exe`, and an icon.
- Logs in `%APPDATA%\Media Share Mapper\Logs\`: every sign-in run and every run with a
  failure, newest 20 kept.

### Changed
- Replaces `shares.ps1`, `Setup-Credentials.ps1`, `Setup-AutoMapTask.ps1` and
  `Drive_Icons.reg`.
- Drives already connected to the right share are left alone instead of being disconnected
  and remapped every time. `-Force` (menu option R) remaps them all.
- Drive icons are written straight to your user settings, which needs no admin rights, so
  they now work from the sign-in task too. Only changed icons are written, and Explorer is
  told to refresh instead of being closed and restarted.
- The sign-in task is now called "Media Share Mapper" (the old "Map Media Network Drives"
  task is replaced). Creating it asks for admin rights itself, and it's made for the
  account that asked even if a different admin account approves it.
- Drives are mapped with the Windows networking API instead of `net use`.

### Fixed
- **The NAS password was passed to `cmdkey` on the command line**, where other programs and
  Windows process logging can see it, and a password containing `&`, `|`, `^`, `%` or `"`
  could be cut short or run part of it as a command. It now goes straight to Windows
  Credential Manager from protected memory.
- **The "letter already in use" retry never ran.** `net use` exits with 2 on any error, not
  the Windows error number, so the check for error 85 never matched, and logs showed
  "FAILED (2)" for every kind of failure. Real error numbers are now reported, with a
  plain-English reason.
- A letter taken by a local disk or USB stick is now reported as such instead of failing
  three times.
- Mapping no longer stops before the icons when one drive fails.
- Found in testing before release: applying drive icons stopped with "Argument types do not
  match" in Windows PowerShell 5.1; the exe stopped with "The handle is invalid" when its
  output was redirected; and the log split each drive's line in two. All three fixed.
  PSScriptAnalyzer is clean.
