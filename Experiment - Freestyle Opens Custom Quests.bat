@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Experiment-FreestyleOpensCustom.ps1"
echo.
pause
