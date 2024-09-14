@echo off
setlocal

:: Set paths for Chrome User Data and the location of the backup zip file
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data\Default"
set "backup_dir=%~dp0backup"
set "zip_file=session_backup.zip"

:: Ensure the backup directory exists and contains the zip file
if not exist "%backup_dir%\%zip_file%" (
    echo Backup zip file not found!
    pause
    exit /b 1
)

:: Unzip the backup (Note the quotes around paths with spaces)
echo Restoring session files...
powershell Expand-Archive -Path "%backup_dir%\%zip_file%" -DestinationPath '"%chrome_profile%"' -Force

:: Restore Local State file (contains encryption keys)
xcopy "%backup_dir%\Local State" "%LOCALAPPDATA%\Google\Chrome\User Data\Local State" /H /Y

echo Restore completed.
pause
endlocal
