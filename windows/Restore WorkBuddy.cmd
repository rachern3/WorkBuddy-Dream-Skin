@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\restore-workbuddy-dream-skin.ps1"
if errorlevel 1 pause
