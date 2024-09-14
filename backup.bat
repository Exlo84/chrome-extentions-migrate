@echo off
setlocal EnableDelayedExpansion

:: Set paths for Chrome User Data and the backup location
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data"
set "backup_dir=%~dp0backup"
set "temp_dir=%backup_dir%\temp"
set "zip_file=chrome_backup.zip"

:: Create backup and temp directories if they don't exist
if not exist "%backup_dir%" mkdir "%backup_dir%"
if not exist "%temp_dir%" mkdir "%temp_dir%"

:: Close Chrome if it's running
taskkill /F /IM chrome.exe 2>NUL

:: Copy the entire Chrome user data folder, including Local State and extensions
echo Copying Chrome profile to temporary location...
xcopy "%chrome_profile%" "%temp_dir%\User Data" /E /I /H /Y /C /R /Q

:: Navigate to the temp directory
cd /d "%temp_dir%"

:: Remove existing zip file if it exists
if exist "%backup_dir%\%zip_file%" del "%backup_dir%\%zip_file%"

:: Create a zip file of the copied Chrome profile
echo Creating zip file...
powershell -Command "& { Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::CreateFromDirectory('%temp_dir%\User Data', '%backup_dir%\%zip_file%'); }"

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