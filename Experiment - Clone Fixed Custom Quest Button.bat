@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Experiment-CloneFixedCustomQuestButton.ps1"
echo.
pause
