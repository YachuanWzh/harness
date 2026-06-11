@echo off
rem Superharness CLI - initializes superharness in the current project directory.
rem Works from both cmd.exe and PowerShell once this bin directory is on PATH.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\lib\install.ps1" -TargetDir "%CD%" %*
exit /b %ERRORLEVEL%
