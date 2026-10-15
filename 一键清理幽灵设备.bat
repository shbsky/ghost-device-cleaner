@echo off
rem ============================================================
rem  One-click ghost device cleaner (scan -> confirm -> clean)
rem  Keep this .bat in the SAME folder as Clean-GhostDevices.ps1
rem ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clean-GhostDevices.ps1" -Clean
echo.
pause
