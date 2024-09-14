@echo off
setlocal EnableDelayedExpansion

:: Set paths
set "chrome_profile=%LOCALAPPDATA%\Google\Chrome\User Data"
set "backup_dir=%~dp0backup"
set "full_zip=%backup_dir%\chrome_full_backup.zip"
set "session_zip=%backup_dir%\chrome_session_backup.zip"
set "log_file=%backup_dir%\chrome_backup.log"
set "temp_dir=%backup_dir%\temp"

:: Create backup directory if it doesn't exist
if not exist "%backup_dir%" mkdir "%backup_dir%"

:: Start logging
echo %date% %time% - Script started > "%log_file%"

:main_menu
cls
echo Choose an option:
echo 1. Backup Chrome data
echo 2. Restore Chrome data
echo 3. Exit
set /p main_choice="Enter your choice (1-3): "

if "%main_choice%"=="1" goto backup_menu
if "%main_choice%"=="2" goto restore_menu
if "%main_choice%"=="3" exit
goto main_menu

:backup_menu
cls
echo Choose backup type:
echo 1. Full backup
echo 2. Session-only backup
set /p backup_type="Enter your choice (1-2): "

cls
echo Choose backup method:
echo 1. Quick (direct zip)
echo 2. Safe (copy to temp folder first)
set /p backup_method="Enter your choice (1-2): "

if "%backup_type%"=="1" (
    set "zip_file=%full_zip%"
    set "backup_name=Full"
) else (
    set "zip_file=%session_zip%"
    set "backup_name=Session"
)

if "%backup_method%"=="1" (
    call :quick_backup
) else (
    call :safe_backup
)
goto main_menu

:quick_backup
echo %date% %time% - Quick %backup_name% backup started >> "%log_file%"
call :close_chrome
if "%backup_name%"=="Full" (
    call :zip_folder "%chrome_profile%" "%zip_file%"
) else (
    call :zip_session_data
)
echo %date% %time% - Quick %backup_name% backup completed >> "%log_file%"
echo Backup completed. Press any key to return to menu.
pause >nul
exit /b

:safe_backup
echo %date% %time% - Safe %backup_name% backup started >> "%log_file%"
call :close_chrome
if exist "%temp_dir%" rmdir /S /Q "%temp_dir%"
mkdir "%temp_dir%"
if "%backup_name%"=="Full" (
    xcopy "%chrome_profile%" "%temp_dir%" /E /H /C /I /Y >> "%log_file%" 2>&1
) else (
    call :copy_session_data "%temp_dir%"
)
call :zip_folder "%temp_dir%" "%zip_file%"
rmdir /S /Q "%temp_dir%"
echo %date% %time% - Safe %backup_name% backup completed >> "%log_file%"
echo Backup completed. Press any key to return to menu.
pause >nul
exit /b

:restore_menu
cls
echo Choose restore type:
echo 1. Full restore
echo 2. Session-only restore
set /p restore_type="Enter your choice (1-2): "

if "%restore_type%"=="1" (
    set "zip_file=%full_zip%"
    set "restore_name=Full"
) else (
    set "zip_file=%session_zip%"
    set "restore_name=Session"
)

call :restore
goto main_menu

:restore
echo %date% %time% - %restore_name% restore started >> "%log_file%"
if not exist "%zip_file%" (
    echo Backup file not found. Please create a backup first.
    echo %date% %time% - Restore failed: Backup file not found >> "%log_file%"
    pause
    exit /b
)
call :close_chrome
if "%restore_name%"=="Full" (
    if exist "%chrome_profile%" rmdir /S /Q "%chrome_profile%"
    mkdir "%chrome_profile%"
    call :unzip_folder "%zip_file%" "%chrome_profile%"
) else (
    call :unzip_session_data
)
echo %date% %time% - %restore_name% restore completed >> "%log_file%"
echo Restore completed. Press any key to return to menu.
pause >nul
exit /b

:close_chrome
echo Closing Chrome...
taskkill /F /IM chrome.exe >nul 2>&1
timeout /t 2 >nul
exit /b

:zip_folder
echo Zipping folder...
tar -cf "%~2" -C "%~1" . >> "%log_file%" 2>&1
exit /b

:unzip_folder
echo Unzipping folder...
tar -xf "%~1" -C "%~2" >> "%log_file%" 2>&1
exit /b

:zip_session_data
echo Zipping session data...
if exist "%temp_dir%" rmdir /S /Q "%temp_dir%"
mkdir "%temp_dir%"
call :copy_session_data "%temp_dir%"
call :zip_folder "%temp_dir%" "%zip_file%"
rmdir /S /Q "%temp_dir%"
exit /b

:copy_session_data
echo Copying session data...
set "dest=%~1"
for %%F in (Cookies "Login Data" "Login Data-journal" Preferences "Web Data" "Web Data-journal" "Sync Data" "History" "History-journal" "Favicons" "Favicons-journal" "Shortcuts" "Shortcuts-journal" "Top Sites" "Visited Links" "Network Action Predictor") do (
    xcopy "%chrome_profile%\Default\%%F" "%dest%\Default\" /H /Y >> "%log_file%" 2>&1
)
for %%D in ("Local Storage" "Session Storage" Sessions "Extension State" IndexedDB Extensions "Local Extension Settings" "Sync Extension Settings" "Service Worker" "shared_proto_db" "IndexedDB" "GPUCache" "Code Cache" "Cache") do (
    xcopy "%chrome_profile%\Default\%%D" "%dest%\Default\%%D\" /E /H /C /I /Y >> "%log_file%" 2>&1
)
xcopy "%chrome_profile%\Local State" "%dest%\" /H /Y >> "%log_file%" 2>&1
xcopy "%chrome_profile%\Network" "%dest%\Network\" /E /H /C /I /Y >> "%log_file%" 2>&1
exit /b

:unzip_session_data
echo Unzipping session data...
if exist "%temp_dir%" rmdir /S /Q "%temp_dir%"
mkdir "%temp_dir%"
call :unzip_folder "%zip_file%" "%temp_dir%"
call :close_chrome
xcopy "%temp_dir%\Default" "%chrome_profile%\Default" /E /H /C /I /Y >> "%log_file%" 2>&1
xcopy "%temp_dir%\Local State" "%chrome_profile%\" /H /Y >> "%log_file%" 2>&1
xcopy "%temp_dir%\Network" "%chrome_profile%\Network\" /E /H /C /I /Y >> "%log_file%" 2>&1
rmdir /S /Q "%temp_dir%"
exit /b