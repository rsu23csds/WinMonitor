@echo off
:: ============================================================================
:: WinInfraMonitor - 1-Click Windows Infrastructure Health Diagnostic Launcher
:: ============================================================================
TITLE WinInfraMonitor - Systems Administration Diagnostic
color 0B
echo.
echo ========================================================================
echo   Launching WinInfraMonitor Health Diagnostic & Automation Engine...
echo ========================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Monitor-Infrastructure.ps1" -OpenReport

echo.
echo [INFO] Health scan complete. Press any key to close this console...
pause >nul
