@echo off
rem Media Share Mapper - double-click to start it.
rem Each time, this makes (or refreshes) the Media Share Mapper shortcut in this folder and in the Start menu,
rem then starts Media Share Mapper from it, in its own console window. After the first run you can use the
rem shortcut, the Start menu or a pinned taskbar button instead.
rem Options are passed straight to the script in this window, e.g.
rem     "Media Share Mapper.cmd" -Action Map -Force
rem The execution-policy bypass applies to Media Share Mapper's own run only; no Windows settings are changed.
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not "%~1"=="" (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Media-Share-Mapper.ps1" %*
    exit /b
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-MediaShareMapperShortcut.ps1" -Launch
if errorlevel 1 pause
