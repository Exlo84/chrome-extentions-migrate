@echo off
setlocal EnableDelayedExpansion

:: Set paths for Chrome User Data and the location of the backup zip file
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data"
set "backup_dir=%~dp0backup"
set "zip_file=session_backup.zip"

:: Ensure the backup directory exists and contains the zip file
if not exist "%backup_dir%\%zip_file%" (
    echo Backup zip file not found!
    pause
    exit /b 1
)

:: Close Chrome if it's running
taskkill /F /IM chrome.exe 2>NUL

:: Create a temporary directory for extraction
set "temp_dir=%backup_dir%\temp_restore"
if not exist "%temp_dir%" mkdir "%temp_dir%"

:: Unzip the backup to the temporary directory
echo Extracting backup files...
powershell -Command "Expand-Archive -Path '%backup_dir%\%zip_file%' -DestinationPath '%temp_dir%' -Force"

:: Restore session-related files and extension data
echo Restoring session files and extension data...
robocopy "%temp_dir%\Default" "%chrome_profile%\Default" "Cookies" "Login Data" "Preferences" "Web Data" "Sync Data" /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\Local Storage" "%chrome_profile%\Default\Local Storage" /E /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\Session Storage" "%chrome_profile%\Default\Session Storage" /E /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\Sessions" "%chrome_profile%\Default\Sessions" /E /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\Extension State" "%chrome_profile%\Default\Extension State" /E /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\IndexedDB" "%chrome_profile%\Default\IndexedDB" /E /COPYALL /R:0 /W:0

:: Restore extension data
robocopy "%temp_dir%\Default\Extensions" "%chrome_profile%\Default\Extensions" /E /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\Local Extension Settings" "%chrome_profile%\Default\Local Extension Settings" /E /COPYALL /R:0 /W:0
robocopy "%temp_dir%\Default\Sync Extension Settings" "%chrome_profile%\Default\Sync Extension Settings" /E /COPYALL /R:0 /W:0

:: Restore Local State file (contains encryption keys and extension info)
copy /Y "%temp_dir%\Local State" "%chrome_profile%\Local State"

:: Clean up temporary directory
rmdir /S /Q "%temp_dir%"

echo Restore completed. You can now start Chrome.
pause
endlocal