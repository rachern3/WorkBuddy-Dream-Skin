@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\customize-theme-windows.ps1"
if errorlevel 1 pause
