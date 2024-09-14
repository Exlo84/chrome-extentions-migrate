#!/bin/bash

# Set paths
chrome_profile="$HOME/.config/google-chrome"
backup_dir="$(dirname "$0")/backup"
full_zip="$backup_dir/chrome_full_backup.tar.gz"
session_zip="$backup_dir/chrome_session_backup.tar.gz"
log_file="$backup_dir/chrome_backup.log"
temp_dir="$backup_dir/temp"

# Create backup directory if it doesn't exist
mkdir -p "$backup_dir"

# Start logging
echo "$(date) - Script started" > "$log_file"

main_menu() {
    while true; do
        clear
        echo "Choose an option:"
        echo "1. Backup Chrome data"
        echo "2. Restore Chrome data"
        echo "3. Exit"
        read -p "Enter your choice (1-3): " main_choice

        case $main_choice in
            1) backup_menu ;;
            2) restore_menu ;;
            3) exit 0 ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

backup_menu() {
    clear
    echo "Choose backup type:"
    echo "1. Full backup"
    echo "2. Session-only backup"
    read -p "Enter your choice (1-2): " backup_type

    clear
    echo "Choose backup method:"
    echo "1. Quick (direct tar)"
    echo "2. Safe (copy to temp folder first)"
    read -p "Enter your choice (1-2): " backup_method

    if [ "$backup_type" == "1" ]; then
        zip_file="$full_zip"
        backup_name="Full"
    else
        zip_file="$session_zip"
        backup_name="Session"
    fi

    if [ "$backup_method" == "1" ]; then
        quick_backup
    else
        safe_backup
    fi
}

quick_backup() {
    echo "$(date) - Quick $backup_name backup started" >> "$log_file"
    close_chrome
    if [ "$backup_name" == "Full" ]; then
        tar_folder "$chrome_profile" "$zip_file"
    else
        tar_session_data
    fi
    echo "$(date) - Quick $backup_name backup completed" >> "$log_file"
    echo "Backup completed. Press any key to return to menu."
    read -n 1 -s
}

safe_backup() {
    echo "$(date) - Safe $backup_name backup started" >> "$log_file"
    close_chrome
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    if [ "$backup_name" == "Full" ]; then
        cp -a "$chrome_profile/." "$temp_dir/" >> "$log_file" 2>&1
    else
        copy_session_data "$temp_dir"
    fi
    tar_folder "$temp_dir" "$zip_file"
    rm -rf "$temp_dir"
    echo "$(date) - Safe $backup_name backup completed" >> "$log_file"
    echo "Backup completed. Press any key to return to menu."
    read -n 1 -s
}

restore_menu() {
    clear
    echo "Choose restore type:"
    echo "1. Full restore"
    echo "2. Session-only restore"
    read -p "Enter your choice (1-2): " restore_type

    if [ "$restore_type" == "1" ]; then
        zip_file="$full_zip"
        restore_name="Full"
    else
        zip_file="$session_zip"
        restore_name="Session"
    fi

    restore
}

restore() {
    echo "$(date) - $restore_name restore started" >> "$log_file"
    if [ ! -f "$zip_file" ]; then
        echo "Backup file not found. Please create a backup first."
        echo "$(date) - Restore failed: Backup file not found" >> "$log_file"
        read -n 1 -s
        return
    fi
    close_chrome
    if [ "$restore_name" == "Full" ]; then
        rm -rf "$chrome_profile"
        mkdir -p "$chrome_profile"
        untar_folder "$zip_file" "$chrome_profile"
    else
        untar_session_data
    fi
    echo "$(date) - $restore_name restore completed" >> "$log_file"
    echo "Restore completed. Press any key to return to menu."
    read -n 1 -s
}

close_chrome() {
    echo "Closing Chrome..."
    killall chrome 2>/dev/null
    sleep 2
}

tar_folder() {
    echo "Compressing folder..."
    tar -czf "$2" -C "$1" . >> "$log_file" 2>&1
}

untar_folder() {
    echo "Extracting folder..."
    tar -xzf "$1" -C "$2" >> "$log_file" 2>&1
}

tar_session_data() {
    echo "Compressing session data..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    copy_session_data "$temp_dir"
    tar_folder "$temp_dir" "$zip_file"
    rm -rf "$temp_dir"
}

copy_session_data() {
    echo "Copying session data..."
    dest="$1"
    files=(
        "Cookies" "Login Data" "Login Data-journal" "Preferences" "Web Data" "Web Data-journal"
        "Sync Data" "History" "History-journal" "Favicons" "Favicons-journal" "Shortcuts"
        "Shortcuts-journal" "Top Sites" "Visited Links" "Network Action Predictor"
    )
    for file in "${files[@]}"; do
        cp -a "$chrome_profile/Default/$file" "$dest/Default/" 2>/dev/null
    done
    
    directories=(
        "Local Storage" "Session Storage" "Sessions" "Extension State" "IndexedDB" "Extensions"
        "Local Extension Settings" "Sync Extension Settings" "Service Worker" "shared_proto_db"
        "GPUCache" "Code Cache" "Cache"
    )
    for dir in "${directories[@]}"; do
        cp -a "$chrome_profile/Default/$dir" "$dest/Default/" 2>/dev/null
    done
    
    cp -a "$chrome_profile/Local State" "$dest/" 2>/dev/null
    cp -a "$chrome_profile/Network" "$dest/" 2>/dev/null
}

untar_session_data() {
    echo "Extracting session data..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    untar_folder "$zip_file" "$temp_dir"
    close_chrome
    cp -a "$temp_dir/Default/." "$chrome_profile/Default/" 2>/dev/null
    cp -a "$temp_dir/Local State" "$chrome_profile/" 2>/dev/null
    cp -a "$temp_dir/Network" "$chrome_profile/" 2>/dev/null
    rm -rf "$temp_dir"
}

# Start the main menu
main_menu