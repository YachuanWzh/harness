@echo off
rem One-time setup: adds superharness\bin to the user PATH.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
exit /b %ERRORLEVEL%
