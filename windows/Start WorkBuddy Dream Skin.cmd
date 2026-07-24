@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\start-workbuddy-dream-skin.ps1" -PromptRestart
if errorlevel 1 pause
