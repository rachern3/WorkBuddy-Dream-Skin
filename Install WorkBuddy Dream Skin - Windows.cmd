@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows\scripts\install-workbuddy-dream-skin.ps1"
if errorlevel 1 pause
