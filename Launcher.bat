@echo off
setlocal
set "LAUNCHER=%~dp0Launcher.ps1"
if not exist "%LAUNCHER%" (
  echo Launcher.ps1 was not found beside this file.
  pause
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
exit /b %ERRORLEVEL%