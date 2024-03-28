#!/bin/bash

# Define source and destination base directories
WIN_USER="YOUR_USERNAME"
SOURCE_BASE="/mnt/windows/Users/$WIN_USER/AppData/Local/Google/Chrome/User Data/Default"
DEST_BASE="$HOME/.config/google-chrome/Default"

# Define directories to copy
DIRS_TO_COPY=("Extensions" "Local Extension Settings" "Local Storage" "Extension State")

# Function to copy directory
copy_directory() {
    local src="$1"
    local dest="$2"
    if [ ! -d "$src" ]; then
        echo "Source directory does not exist: $src"
        return 1
    fi
    echo "Copying $src to $dest..."
    cp -r "$src" "$dest"
}

# Backup and copy each directory
for dir in "${DIRS_TO_COPY[@]}"; do
    src_dir="$SOURCE_BASE/$dir"
    dest_dir="$DEST_BASE/$dir"
    backup_dir="${dest_dir}_backup_$(date +%Y%m%d_%H%M%S)"

    # Backup the existing directory in Ubuntu
    if [ -d "$dest_dir" ]; then
        echo "Backing up existing $dir directory..."
        mv "$dest_dir" "$backup_dir"
        if [ ! -d "$backup_dir" ]; then
            echo "Failed to backup $dir. Aborting script."
            exit 1
        fi
        echo "Backup of $dir completed successfully."
    fi

    # Copy from Windows to Ubuntu
    copy_directory "$src_dir" "$DEST_BASE"
done

echo "All specified directories have been copied."
echo "Please restart Chrome to see the changes."
