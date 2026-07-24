@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\verify-workbuddy-dream-skin.ps1"
if errorlevel 1 pause
