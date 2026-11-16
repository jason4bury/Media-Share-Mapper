@echo off
rem Starts Media Share Mapper from the repo's script, in this console window. Options are passed
rem straight to the script, e.g.  "Start Media Share Mapper.cmd" -Action Map -Force
rem The execution-policy bypass applies to this run only; no Windows settings are changed.
rem Settings are kept in %APPDATA%\Media Share Mapper.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Media-Share-Mapper.ps1" %*
