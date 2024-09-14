@echo off
setlocal

:: Set paths for Chrome User Data and the backup location
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data\Default"
set "backup_dir=%~dp0backup"
set "zip_file=session_backup.zip"

:: Create backup directory if it doesn't exist
if not exist "%backup_dir%" mkdir "%backup_dir%"

:: Only copy the essential session files
echo Copying session-related files to backup location...
xcopy "%chrome_profile%\Cookies" "%backup_dir%\Cookies" /H /Y
xcopy "%chrome_profile%\Login Data" "%backup_dir%\Login Data" /H /Y
xcopy "%chrome_profile%\Preferences" "%backup_dir%\Preferences" /H /Y
xcopy "%chrome_profile%\Local Storage" "%backup_dir%\Local Storage" /E /I /H /Y
xcopy "%chrome_profile%\Sessions" "%backup_dir%\Sessions" /E /I /H /Y
xcopy "%chrome_profile%\Extension State" "%backup_dir%\Extension State" /E /I /H /Y

:: Also copy the Local State file (contains encryption keys)
xcopy "%LOCALAPPDATA%\Google\Chrome\User Data\Local State" "%backup_dir%\Local State" /H /Y

:: Navigate to the backup directory
cd /d "%backup_dir%"

:: Create a zip file of the copied session files
echo Creating zip file...
powershell Compress-Archive -Path "*" -DestinationPath "%zip_file%" -Force

echo Backup completed. Zip file saved at: %backup_dir%\%zip_file%

pause
endlocal
