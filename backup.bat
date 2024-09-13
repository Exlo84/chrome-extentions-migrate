@echo off
setlocal

:: Set paths for Chrome User Data and the backup location
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data"
set "backup_dir=%~dp0backup"
set "zip_file=chrome_backup.zip"

:: Create backup directory if it doesn't exist
if not exist "%backup_dir%" mkdir "%backup_dir%"

:: Copy the entire Chrome user data folder to the backup directory
echo Copying Chrome profile to backup location...
xcopy "%chrome_profile%" "%backup_dir%\User Data" /E /I /H /Y

:: Navigate to the backup directory
cd /d "%backup_dir%"

:: Create a zip file of the copied Chrome profile (Note the quotes around paths with spaces)
echo Creating zip file...
powershell Compress-Archive -Path '"User Data"' -DestinationPath "%zip_file%" -Force

:: Clean up the copied files after zipping (optional)
rmdir /S /Q "User Data"

echo Backup completed. Zip file saved at: %backup_dir%\%zip_file%

pause
endlocal
