@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Experiment-ReuseFixedFurnitureSlot.ps1"
echo.
pause
