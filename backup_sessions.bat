@echo off
setlocal EnableDelayedExpansion

:: Set paths for Chrome User Data and the backup location
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data"
set "backup_dir=%~dp0backup"
set "temp_dir=%backup_dir%\temp"
set "zip_file=session_backup.zip"

:: Create backup and temp directories if they don't exist
if not exist "%backup_dir%" mkdir "%backup_dir%"
if not exist "%temp_dir%" mkdir "%temp_dir%"

:: Close Chrome if it's running
taskkill /F /IM chrome.exe 2>NUL

:: Copy session-related files and extension data to temp directory
echo Copying session-related files and extension data to temporary location...
robocopy "%chrome_profile%\Default" "%temp_dir%\Default" "Cookies" "Login Data" "Preferences" "Web Data" "Sync Data" /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\Local Storage" "%temp_dir%\Default\Local Storage" /E /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\Session Storage" "%temp_dir%\Default\Session Storage" /E /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\Sessions" "%temp_dir%\Default\Sessions" /E /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\Extension State" "%temp_dir%\Default\Extension State" /E /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\IndexedDB" "%temp_dir%\Default\IndexedDB" /E /COPYALL /R:0 /W:0

:: Copy extension data
robocopy "%chrome_profile%\Default\Extensions" "%temp_dir%\Default\Extensions" /E /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\Local Extension Settings" "%temp_dir%\Default\Local Extension Settings" /E /COPYALL /R:0 /W:0
robocopy "%chrome_profile%\Default\Sync Extension Settings" "%temp_dir%\Default\Sync Extension Settings" /E /COPYALL /R:0 /W:0

:: Copy the Local State file (contains encryption keys and extension info)
robocopy "%chrome_profile%" "%temp_dir%" "Local State" /COPYALL /R:0 /W:0

:: Navigate to the temp directory
cd /d "%temp_dir%"

:: Remove existing zip file if it exists
if exist "%backup_dir%\%zip_file%" del "%backup_dir%\%zip_file%"

:: Create a zip file of the copied session files and extension data
echo Creating zip file...
powershell -Command "& { Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::CreateFromDirectory('%temp_dir%', '%backup_dir%\%zip_file%'); }"

:: Check if zip file was created successfully
if exist "%backup_dir%\%zip_file%" (
    echo Backup completed. Zip file saved at: %backup_dir%\%zip_file%
    
    :: Calculate and display the size of the backup
    for %%I in ("%backup_dir%\%zip_file%") do set "size=%%~zI"
    set /a size_mb=%size% / 1048576
    echo Backup size: %size_mb% MB
) else (
    echo Failed to create zip file. Please check for errors.
)

:: Clean up the temporary directory
cd /d "%backup_dir%"
rmdir /S /Q "%temp_dir%"

pause
endlocal