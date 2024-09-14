# Chrome Backup and Restore Scripts

This repository contains two scripts for backing up and restoring Google Chrome user data: one for Windows and one for Ubuntu. These scripts allow users to create full or session-only backups of their Chrome profiles and restore them when needed, helping to preserve browsing sessions, login states, and other user data.

## Features

- Full backup and restore of Chrome user data
- Session-only backup and restore for faster operations
- Option for quick or safe backup methods
- Logging of all operations for easy troubleshooting
- Cross-platform support (Windows and Ubuntu)

## Windows Script: `chrome_advanced_backup_restore.bat`

### Requirements

- Windows operating system
- Google Chrome installed

### Usage

1. Download the `chrome_advanced_backup_restore.bat` file.
2. Double-click the file to run it, or open a command prompt and navigate to the directory containing the script, then run:
   ```
   chrome_advanced_backup_restore.bat
   ```
3. Follow the on-screen prompts to backup or restore your Chrome data.

## Ubuntu Script: `chrome_backup_restore.sh`

### Requirements

- Ubuntu (or other Linux distribution)
- Google Chrome installed
- Bash shell

### Usage

1. Download the `chrome_backup_restore.sh` file.
2. Make the script executable:
   ```
   chmod +x chrome_backup_restore.sh
   ```
3. Run the script:
   ```
   ./chrome_backup_restore.sh
   ```
4. Follow the on-screen prompts to backup or restore your Chrome data.

## Backup Types

Both scripts offer two types of backups:

1. **Full Backup**: Backs up the entire Chrome user profile, including all settings, extensions, and data.
2. **Session-only Backup**: Backs up only the essential files needed to restore your current browsing session, including login states, cookies, and recent history.

## Backup Methods

The scripts provide two backup methods:

1. **Quick**: Directly compresses the Chrome profile folder.
2. **Safe**: Copies the data to a temporary folder before compressing, ensuring the integrity of the original data.

## Restoring Data

To restore your Chrome data:

1. Run the script and choose the "Restore Chrome data" option.
2. Select whether you want to perform a full restore or a session-only restore.
3. The script will automatically close Chrome, restore the selected data, and inform you when the process is complete.

## Important Notes

- Always close Chrome before starting a backup or restore operation. The scripts attempt to close Chrome automatically, but it's best to ensure it's not running before you start.
- The backup files are stored in a `backup` folder in the same directory as the script.
- Session-only backups are smaller and faster but may not include all Chrome data. Use full backups for complete data preservation.
- These scripts are provided as-is and should be used at your own risk. Always ensure you have additional backups of important data.

## Troubleshooting

If you encounter any issues:

1. Check the log file created in the `backup` folder for any error messages.
2. Ensure you have the necessary permissions to read and write in the Chrome user data directory.
3. If you're having trouble with session-only restores, try using a full restore instead.

## Contributing

Contributions to improve these scripts are welcome! Please feel free to submit issues or pull requests on GitHub.
