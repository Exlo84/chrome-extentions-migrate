#!/bin/bash

# Define paths
CHROME_PROFILE="$HOME/.config/google-chrome/Default"
BACKUP_DIR="$(dirname "$0")/backup"
ZIP_FILE="$BACKUP_DIR/session_backup.zip"

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

# Create the Chrome profile directory if it doesn't exist
if [ ! -d "$CHROME_PROFILE" ]; then
  mkdir -p "$CHROME_PROFILE"
fi

# Unzip the backup to the Chrome profile directory
echo "Restoring session files..."
unzip -o "$ZIP_FILE" -d "$CHROME_PROFILE"

# Restore Local State file
if [ -f "$BACKUP_DIR/Local State" ]; then
  cp "$BACKUP_DIR/Local State" "$CHROME_PROFILE/../Local State"
fi

echo "Restore completed."
