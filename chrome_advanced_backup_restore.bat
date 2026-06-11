@echo off
:: Chrome Backup & Restore — Launcher
:: Double-click this file to run the PowerShell script.

:: Check if we have PowerShell available
where powershell >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: PowerShell not found. Please install PowerShell 5.1 or later.
    pause
    exit /b 1
)

:: Launch the PowerShell script with bypass execution policy
:: (no permanent system changes — only affects this session)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0chrome_backup_restore.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Script exited with error code %ERRORLEVEL%.
    echo Check the backup\chrome_backup.log file for details.
    pause
)