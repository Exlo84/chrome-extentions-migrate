#!/bin/bash

# Define paths
CHROME_PROFILE="$HOME/.config/google-chrome/Default"
BACKUP_DIR="$(dirname "$0")/backup"
ZIP_FILE="$BACKUP_DIR/session_backup.zip"
TEMP_DIR="$BACKUP_DIR/temp_restore"

# Check if the zip file exists
if [ ! -f "$ZIP_FILE" ]; then
  echo "Backup zip file not found!"
  exit 1
fi

# Check if unzip is installed
if ! command -v unzip &> /dev/null; then
  echo "Error: unzip is not installed. Please install it and try again."
  exit 1
fi

# Close Chrome if it's running
pkill chrome

# Create the Chrome profile directory if it doesn't exist
mkdir -p "$CHROME_PROFILE"

# Create and clean the temporary directory
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Unzip the backup to the temporary directory
echo "Extracting backup files..."
unzip -q "$ZIP_FILE" -d "$TEMP_DIR"

# Restore session-related files and extension data
echo "Restoring session files and extension data..."
cp -rf "$TEMP_DIR/Default/"* "$CHROME_PROFILE/"
cp -f "$TEMP_DIR/Local State" "$HOME/.config/google-chrome/Local State"

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo "Restore completed. You can now start Chrome."