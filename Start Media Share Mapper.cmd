@echo off
rem Starts Media Share Mapper from the script. The execution-policy bypass applies to this run only;
rem no Windows settings are changed. Settings are kept in %APPDATA%\Media Share Mapper.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Media-Share-Mapper.ps1" %*
