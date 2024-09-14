#!/bin/bash

# Define paths
CHROME_PROFILE="$HOME/.config/google-chrome"
BACKUP_DIR="$(dirname "$0")/backup"
ZIP_FILE="$BACKUP_DIR/chrome_backup.zip"

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
echo "Restoring Chrome profile..."
unzip -o "$ZIP_FILE" -d "$CHROME_PROFILE"

# Check if unzip was successful
if [ $? -eq 0 ]; then
  echo "Restore completed successfully."
else
  echo "Error: Failed to restore the Chrome profile."
  exit 1
fi
