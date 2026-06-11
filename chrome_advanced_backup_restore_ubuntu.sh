#!/bin/bash

# --- CONFIGURATION ------------------------------------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="$script_dir/backup"
log_file="$backup_dir/chrome_backup.log"
temp_dir="$backup_dir/_temp_working"
chrome_profile="$HOME/.config/google-chrome"

# Create backup directory if it doesn't exist
mkdir -p "$backup_dir"

# Session-only files and folders to include
session_files=(
    "Login Data" "Login Data-journal"
    "Preferences" "Preferences-journal"
    "Web Data" "Web Data-journal"
    "Sync Data"
    "History" "History-journal"
    "Favicons" "Favicons-journal"
    "Shortcuts" "Shortcuts-journal"
    "Top Sites" "Top Sites-journal"
    "Visited Links"
    "Network Action Predictor"
    "Bookmarks" "Bookmarks-journal"
)

session_dirs=(
    "Network"
    "Extensions"
    "Extension State"
    "Local Extension Settings"
    "Sync Extension Settings"
    "IndexedDB"
    "Local Storage"
    "Session Storage"
    "Sessions"
    "Service Worker"
    "shared_proto_db"
    "Sync Data"
)

# --- COLOURS ------------------------------------------------------------------
write_color() {
    local text="$1"
    local color="$2"
    local no_newline="$3"
    local code="37" # White
    case "$color" in
        Cyan) code="36" ;;
        DarkCyan) code="36" ;;
        Green) code="32" ;;
        Red) code="31" ;;
        Yellow) code="33" ;;
        DarkGray) code="90" ;;
    esac
    if [ "$no_newline" == "-n" ]; then
        printf "\e[${code}m%s\e[0m" "$text"
    else
        printf "\e[${code}m%s\e[0m\n" "$text"
    fi
}

write_header() {
    local title="$1"
    local width=72
    local line=$(printf '=%.0s' $(seq 1 $width))
    echo
    write_color "  +$line+" "Cyan"
    printf "  |\e[36m%-72s\e[0m|\n" "  $title"
    write_color "  +$line+" "Cyan"
    echo
}

write_section() {
    local title="$1"
    echo
    write_color "  -- $title " "DarkCyan" -n
    local len=${#title}
    local rem=$((60 - len))
    if [ $rem -lt 2 ]; then rem=2; fi
    local dash=$(printf -- '-%.0s' $(seq 1 $rem))
    write_color "$dash" "DarkCyan"
}

write_ok()   { write_color "  [OK] $1" "Green"; }
write_warn() { write_color "  [i]  $1" "Cyan"; }
write_err()  { write_color "  [X]  $1" "Red"; }
write_info() { write_color "  [i]  $1" "Cyan"; }

# --- LOGGING ------------------------------------------------------------------
write_log() {
    local message="$1"
    local level="${2:-INFO}"
    local stamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$stamp] [$level] $message" >> "$log_file" 2>/dev/null
}

initialize_log() {
    local stamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$stamp] Chrome Backup/Restore Tool Started" > "$log_file"
    echo "[$stamp] Script Dir: $script_dir" >> "$log_file"
    echo "[$stamp] Backup Dir: $backup_dir" >> "$log_file"
}

# --- VALIDATION ---------------------------------------------------------------
test_prerequisites() {
    write_section "System Validation"
    local all_ok=true

    # 1. Tools check
    if ! command -v zip &>/dev/null || ! command -v unzip &>/dev/null; then
        write_err "zip and unzip are required. Please install via: sudo apt install zip unzip"
        all_ok=false
    else
        write_ok "Compression tools: zip & unzip verified"
    fi

    # 2. Python check
    if ! command -v python3 &>/dev/null; then
        write_err "Python3 is required for profile parsing and cookie syncing. Please install it."
        all_ok=false
    else
        write_ok "Python3: $(python3 --version | head -n1)"
    fi

    # 3. Chrome User Data check
    if [ ! -d "$chrome_profile" ]; then
        write_err "Chrome config folder not found at: $chrome_profile"
        write_err "Is Chrome installed and has it been run at least once?"
        all_ok=false
    else
        local size_bytes=$(du -sb "$chrome_profile" 2>/dev/null | cut -f1)
        local size_mb=$((size_bytes / 1024 / 1024))
        write_ok "Chrome User Data: $chrome_profile ($size_mb MB)"
    fi

    echo
    return $([ "$all_ok" = true ] && echo 0 || echo 1)
}

close_chrome() {
    write_info "Checking for running Chrome processes..."
    if pgrep -x "chrome" &>/dev/null || pgrep -x "google-chrome" &>/dev/null; then
        write_info "Chrome process(es) found. Closing Chrome..."
        write_log "Closing running Chrome processes"
        killall chrome google-chrome google-chrome-stable &>/dev/null
        sleep 2
        
        # Double check
        if pgrep -x "chrome" &>/dev/null || pgrep -x "google-chrome" &>/dev/null; then
            write_info "Action required: Please close Chrome manually, then press Enter."
            read -r -p "  Press Enter when Chrome is closed "
        else
            write_ok "Chrome closed successfully."
        fi
    else
        write_ok "Chrome is not running."
    fi
    sleep 1
}

# --- PROFILE IDENTIFICATION ---------------------------------------------------
get_profiles() {
    python3 -c '
import os, json
user_data = os.path.expanduser("~/.config/google-chrome")
profiles = []
if os.path.exists(user_data):
    for entry in os.scandir(user_data):
        if entry.is_dir() and (entry.name == "Default" or entry.name.startswith("Profile ")):
            pref_path = os.path.join(entry.path, "Preferences")
            has_cookies = os.path.exists(os.path.join(entry.path, "Cookies")) or os.path.exists(os.path.join(entry.path, "Network", "Cookies"))
            if os.path.exists(pref_path) or has_cookies:
                email = ""
                name = ""
                if os.path.exists(pref_path):
                    try:
                        with open(pref_path, "r", encoding="utf-8") as f:
                            data = json.load(f)
                            email = data.get("account_info", [{}])[0].get("email", "")
                            if not email:
                                email = data.get("google", {}).get("services", {}).get("username", "")
                            if not email:
                                email = data.get("google", {}).get("services", {}).get("signin", {}).get("username", "")
                            name = data.get("profile", {}).get("name", "")
                    except:
                        pass
                profiles.append((entry.name, email, name))
for p in sorted(profiles, key=lambda x: 0 if x[0] == "Default" else int(x[0].split()[1]) if len(x[0].split()) > 1 else 999):
    print(f"{p[0]}|{p[1]}|{p[2]}")
' 2>/dev/null
}

select_profiles() {
    local action="$1"
    mapfile -t profile_lines < <(get_profiles)
    if [ ${#profile_lines[@]} -eq 0 ]; then
        write_warn "No Chrome profiles detected."
        return 1
    fi

    echo
    write_color "  Select Chrome profile(s) to $action:" "Cyan"
    echo
    printf "    %-4s %-16s %-27s %s\n" "ID" "Profile Folder" "Signed-in Email" "Friendly Name"
    printf "    %-4s %-16s %-27s %s\n" "--" "--------------" "---------------" "-------------"

    local i=0
    for line in "${profile_lines[@]}"; do
        IFS='|' read -r folder email name <<< "$line"
        [ -z "$email" ] && email="(not signed in)"
        [ -z "$name" ] && name=""
        printf "    [%-2d] %-16s %-27s %s\n" $((i+1)) "$folder" "$email" "$name"
        i=$((i+1))
    done
    echo "    [A]  All Profiles"
    echo

    while true; do
        read -r -p "  Enter ID(s) (comma-separated, e.g. 1,3) or A for All: " user_choice
        [ -z "$user_choice" ] && return 1
        user_choice=$(echo "$user_choice" | tr '[:lower:]' '[:upper:]' | xargs)

        if [ "$user_choice" == "A" ] || [ "$user_choice" == "ALL" ]; then
            selected_folders=()
            for line in "${profile_lines[@]}"; do
                IFS='|' read -r folder email name <<< "$line"
                selected_folders+=("$folder")
            done
            return 0
        fi

        selected_folders=()
        IFS=',' read -ra ADDR <<< "$user_choice"
        local valid=true
        for id_str in "${ADDR[@]}"; do
            id_str=$(echo "$id_str" | xargs)
            if [[ "$id_str" =~ ^[0-9]+$ ]]; then
                local idx=$((id_str - 1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#profile_lines[@]} ]; then
                    IFS='|' read -r folder email name <<< "${profile_lines[$idx]}"
                    selected_folders+=("$folder")
                else
                    write_err "Invalid ID: $id_str (out of range)"
                    valid=false
                    break
                fi
            else
                write_err "Invalid input: $id_str"
                valid=false
                break
            fi
        done

        if [ "$valid" = true ] && [ ${#selected_folders[@]} -gt 0 ]; then
            return 0
        fi
    done
}

get_profiles_in_zip() {
    local zip_file="$1"
    local tmp_extract=$(mktemp -d)
    
    # Extract only the Preferences files inside zip to get emails/names
    local pref_entries=$(unzip -l "$zip_file" 2>/dev/null | grep "/Preferences$" | awk '{print $4}')
    
    for entry in $pref_entries; do
        unzip -p "$zip_file" "$entry" > "$tmp_extract/$(basename "$(dirname "$entry")")_Preferences" 2>/dev/null
    done
    
    python3 -c '
import os, json, sys
tmp_dir = sys.argv[1]
profiles = []
if os.path.exists(tmp_dir):
    for f_name in os.listdir(tmp_dir):
        if f_name.endswith("_Preferences"):
            folder = f_name.replace("_Preferences", "")
            pref_path = os.path.join(tmp_dir, f_name)
            email = ""
            name = ""
            try:
                with open(pref_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    email = data.get("account_info", [{}])[0].get("email", "")
                    if not email:
                        email = data.get("google", {}).get("services", {}).get("username", "")
                    if not email:
                        email = data.get("google", {}).get("services", {}).get("signin", {}).get("username", "")
                    name = data.get("profile", {}).get("name", "")
            except:
                pass
            profiles.append((folder, email, name))
for p in sorted(profiles, key=lambda x: 0 if x[0] == "Default" else int(x[0].split()[1]) if len(x[0].split()) > 1 else 999):
    print(f"{p[0]}|{p[1]}|{p[2]}")
' "$tmp_extract" 2>/dev/null
    rm -rf "$tmp_extract"
}

select_restore_profiles() {
    local zip_file="$1"
    mapfile -t zip_profiles < <(get_profiles_in_zip "$zip_file")
    if [ ${#zip_profiles[@]} -eq 0 ]; then
        write_warn "No profiles found in the backup file."
        return 1
    fi

    echo
    write_color "  Select Chrome profile(s) to restore from backup:" "Cyan"
    echo
    printf "    %-4s %-16s %-27s %s\n" "ID" "Profile Folder" "Signed-in Email" "Friendly Name"
    printf "    %-4s %-16s %-27s %s\n" "--" "--------------" "---------------" "-------------"

    local i=0
    for line in "${zip_profiles[@]}"; do
        IFS='|' read -r folder email name <<< "$line"
        [ -z "$email" ] && email="(not signed in)"
        [ -z "$name" ] && name=""
        printf "    [%-2d] %-16s %-27s %s\n" $((i+1)) "$folder" "$email" "$name"
        i=$((i+1))
    done
    echo "    [A]  All Profiles"
    echo

    while true; do
        read -r -p "  Enter ID(s) (comma-separated, e.g. 1,3) or A for All: " user_choice
        [ -z "$user_choice" ] && return 1
        user_choice=$(echo "$user_choice" | tr '[:lower:]' '[:upper:]' | xargs)

        if [ "$user_choice" == "A" ] || [ "$user_choice" == "ALL" ]; then
            selected_restore_folders=()
            return 0
        fi

        selected_restore_folders=()
        IFS=',' read -ra ADDR <<< "$user_choice"
        local valid=true
        for id_str in "${ADDR[@]}"; do
            id_str=$(echo "$id_str" | xargs)
            if [[ "$id_str" =~ ^[0-9]+$ ]]; then
                local idx=$((id_str - 1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#zip_profiles[@]} ]; then
                    IFS='|' read -r folder email name <<< "${zip_profiles[$idx]}"
                    selected_restore_folders+=("$folder")
                else
                    write_err "Invalid ID: $id_str (out of range)"
                    valid=false
                    break
                fi
            else
                write_err "Invalid input: $id_str"
                valid=false
                break
            fi
        done

        if [ "$valid" = true ] && [ ${#selected_restore_folders[@]} -gt 0 ]; then
            return 0
        fi
    done
}

select_backup_file() {
    local type="$1"
    local pattern=""
    if [ "$type" == "Full" ]; then
        pattern="chrome_full_backup*.zip"
    else
        pattern="chrome_session_backup*.zip"
    fi

    mapfile -t files < <(find "$backup_dir" -maxdepth 1 -name "$pattern" -type f | sort)
    if [ ${#files[@]} -eq 0 ]; then
        return 1
    fi
    if [ ${#files[@]} -eq 1 ]; then
        selected_zip_file="${files[0]}"
        return 0
    fi

    echo
    write_color "  Multiple $type backups found. Please select which one to restore:" "Cyan"
    echo
    local i=0
    for f in "${files[@]}"; do
        local fname=$(basename "$f")
        local fsize=$(du -mh "$f" | cut -f1)
        local fdate=$(date -r "$f" "+%Y-%m-%d %H:%M")
        printf "    [%d]  %-40s (%s, Created: %s)\n" $((i+1)) "$fname" "$fsize" "$fdate"
        i=$((i+1))
    done
    echo

    while true; do
        read -r -p "  Enter choice (1-${#files[@]}): " choice
        [ -z "$choice" ] && return 1
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#files[@]} ]; then
                selected_zip_file="${files[$idx]}"
                return 0
            fi
        fi
        write_err "Invalid choice."
    done
}

# --- AUTOMATIC COOKIE SYNC (DPAPI BYPASS) --------------------------------------
invoke_cookie_migration() {
    local mode="$1"
    local profile_name="$2"
    local json_path="$3"

    write_info "Automatic Cookie $mode for Profile: $profile_name..."

    if ! command -v python3 &>/dev/null; then
        write_err "Python3 is not installed. Skipping cookie sync."
        return 1
    fi

    if [ ! -f "$script_dir/cookie_sync.py" ]; then
        write_err "cookie_sync.py helper script not found in $script_dir."
        return 1
    fi

    python3 "$script_dir/cookie_sync.py" "$mode" "$chrome_profile" "$profile_name" "$json_path"
    local sync_status=$?

    if [ $sync_status -eq 0 ]; then
        write_ok "Automatic cookie sync successful for $profile_name."
        return 0
    else
        write_err "Automatic cookie sync failed for $profile_name."
        return 1
    fi
}

# --- BACKUP LOGIC -------------------------------------------------------------
start_full_backup() {
    write_header "Full Backup"

    if ! select_profiles "Backup"; then
        write_warn "No profiles selected for backup. Operation cancelled."
        return 1
    fi

    local is_all=false
    mapfile -t total_profiles < <(get_profiles)
    if [ ${#selected_folders[@]} -eq ${#total_profiles[@]} ]; then
        is_all=true
        write_info "All profiles selected. Performing full User Data backup."
    else
        write_info "Selected profile(s) to backup:"
        for f in "${selected_folders[@]}"; do
            write_color "     - $f" "DarkGray"
        done
    fi

    read -r -p "  Do you want to automatically backup your login sessions (cookies) for selected profile(s)? (YES/NO): " sync_cookies
    if [ "${sync_cookies^^}" == "YES" ]; then
        local cookie_backup_dir="$backup_dir/cookies"
        mkdir -p "$cookie_backup_dir"
        close_chrome
        for f in "${selected_folders[@]}"; do
            invoke_cookie_migration "EXPORT" "$f" "$cookie_backup_dir/cookies_$f.json"
        done
    fi

    write_info "Collecting files for backup..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    close_chrome

    if [ "$is_all" = true ]; then
        cp -a "$chrome_profile/." "$temp_dir/" 2>/dev/null
    else
        # Copy root files
        find "$chrome_profile" -maxdepth 1 -type f -exec cp -a {} "$temp_dir/" \; 2>/dev/null
        # Copy selected folders
        for folder in "${selected_folders[@]}"; do
            if [ -d "$chrome_profile/$folder" ]; then
                mkdir -p "$temp_dir/$folder"
                cp -a "$chrome_profile/$folder/." "$temp_dir/$folder/" 2>/dev/null
            fi
        done
    fi

    write_info "Compressing backup..."
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local zip_path="$backup_dir/chrome_full_backup_ubuntu_$timestamp.zip"
    (cd "$temp_dir" && zip -rq "$zip_path" .)
    rm -rf "$temp_dir"

    local zip_mb=$(du -mh "$zip_path" | cut -f1)
    write_ok "Full backup saved: $zip_path ($zip_mb)"
    write_log "Full backup complete: $zip_path ($zip_mb)"
}

start_session_backup() {
    write_header "Session-Only Backup"

    if ! select_profiles "Backup"; then
        write_warn "No profiles selected for backup. Operation cancelled."
        return 1
    fi

    local is_all=false
    mapfile -t total_profiles < <(get_profiles)
    if [ ${#selected_folders[@]} -eq ${#total_profiles[@]} ]; then
        is_all=true
        write_info "All profiles selected."
    else
        write_info "Selected profile(s) to backup:"
        for f in "${selected_folders[@]}"; do
            write_color "     - $f" "DarkGray"
        done
    fi

    read -r -p "  Do you want to automatically backup your login sessions (cookies) for selected profile(s)? (YES/NO): " sync_cookies
    if [ "${sync_cookies^^}" == "YES" ]; then
        local cookie_backup_dir="$backup_dir/cookies"
        mkdir -p "$cookie_backup_dir"
        close_chrome
        for f in "${selected_folders[@]}"; do
            invoke_cookie_migration "EXPORT" "$f" "$cookie_backup_dir/cookies_$f.json"
        done
    fi

    write_info "Collecting files for session backup..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    close_chrome

    # Copy Local State
    if [ -f "$chrome_profile/Local State" ]; then
        cp -a "$chrome_profile/Local State" "$temp_dir/" 2>/dev/null
    fi

    # Copy selected folders session data
    for folder in "${selected_folders[@]}"; do
        local p_dir="$chrome_profile/$folder"
        if [ -d "$p_dir" ]; then
            # files
            for file in "${session_files[@]}"; do
                if [ -f "$p_dir/$file" ]; then
                    mkdir -p "$temp_dir/$folder"
                    cp -a "$p_dir/$file" "$temp_dir/$folder/" 2>/dev/null
                fi
            done
            # directories
            for dir in "${session_dirs[@]}"; do
                if [ -d "$p_dir/$dir" ]; then
                    mkdir -p "$temp_dir/$folder/$dir"
                    cp -a "$p_dir/$dir/." "$temp_dir/$folder/$dir/" 2>/dev/null
                fi
            done
        fi
    done

    write_info "Compressing session backup..."
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local zip_path="$backup_dir/chrome_session_backup_ubuntu_$timestamp.zip"
    (cd "$temp_dir" && zip -rq "$zip_path" .)
    rm -rf "$temp_dir"

    local zip_mb=$(du -mh "$zip_path" | cut -f1)
    write_ok "Session backup saved: $zip_path ($zip_mb)"
    write_log "Session backup complete: $zip_path ($zip_mb)"
}

# --- RESTORE LOGIC ------------------------------------------------------------
start_full_restore() {
    write_header "Full Restore"

    select_backup_file "Full"
    if [ $? -ne 0 ] || [ -z "$selected_zip_file" ]; then
        write_err "No Full backup files found in: $backup_dir"
        return 1
    fi

    local zip_mb=$(du -mh "$selected_zip_file" | cut -f1)
    write_info "Backup file: $(basename "$selected_zip_file")"
    write_info "Backup size: $zip_mb"

    if ! select_restore_profiles "$selected_zip_file"; then
        write_warn "Restore cancelled."
        return 1
    fi

    local is_all=true
    if [ ${#selected_restore_folders[@]} -gt 0 ]; then
        is_all=false
        write_info "Selected profile(s) to restore:"
        for f in "${selected_restore_folders[@]}"; do
            write_color "     - $f" "DarkGray"
        done
    else
        write_info "Restoring all profiles."
    fi

    echo
    write_color "  +-------------------------------------------------------------+" "Cyan"
    write_color "  |  PORTABILITY & RESTORE PREVIEW                              |" "Cyan"
    write_color "  |   [OK] MetaMask and all extensions WILL be restored         |" "Green"
    write_color "  |   [OK] Bookmarks, history, and settings WILL be restored    |" "Green"
    write_color "  |   [i]  Note: Sites requiring login will prompt for password |" "Cyan"
    write_color "  +-------------------------------------------------------------+" "Cyan"
    echo

    read -r -p "  Type YES to confirm restore: " confirm
    if [ "${confirm^^}" != "YES" ]; then
        write_warn "Restore cancelled by user."
        return 1
    fi

    close_chrome

    # Clean existing data depending on selection
    if [ "$is_all" = true ]; then
        write_info "Removing current Chrome User Data..."
        rm -rf "$chrome_profile"
        mkdir -p "$chrome_profile"
        write_info "Extracting backup..."
        unzip -oq "$selected_zip_file" -d "$chrome_profile"
    else
        # Remove only selected folders
        for folder in "${selected_restore_folders[@]}"; do
            write_info "Removing existing profile directory: $chrome_profile/$folder"
            rm -rf "$chrome_profile/$folder"
        done
        
        # Build unzip filter list
        local unzip_args=()
        for folder in "${selected_restore_folders[@]}"; do
            unzip_args+=("$folder/*")
        done
        unzip_args+=("Local State") # Always restore global configuration
        
        write_info "Extracting selected profile(s)..."
        unzip -oq "$selected_zip_file" "${unzip_args[@]}" -d "$chrome_profile"
    fi

    # Cookie Import Hook
    local cookie_backup_dir="$backup_dir/cookies"
    if [ -d "$cookie_backup_dir" ]; then
        mapfile -t cookie_files < <(find "$cookie_backup_dir" -name "cookies_*.json")
        if [ ${#cookie_files[@]} -gt 0 ]; then
            local matched_cookies=()
            for cf in "${cookie_files[@]}"; do
                local fname=$(basename "$cf")
                local p_folder="${fname#cookies_}"
                p_folder="${p_folder%.json}"
                if [ "$is_all" = true ] || [[ " ${selected_restore_folders[*]} " =~ " ${p_folder} " ]]; then
                    matched_cookies+=("$cf")
                fi
            done

            if [ ${#matched_cookies[@]} -gt 0 ]; then
                echo
                read -r -p "  Found backed up login sessions (cookies) for selected profile(s). Do you want to automatically import them? (YES/NO): " import_cookies
                if [ "${import_cookies^^}" == "YES" ]; then
                    close_chrome
                    for cf in "${matched_cookies[@]}"; do
                        local fname=$(basename "$cf")
                        local p_folder="${fname#cookies_}"
                        p_folder="${p_folder%.json}"
                        invoke_cookie_migration "IMPORT" "$p_folder" "$cf"
                    done
                fi
            fi
        fi
    fi

    write_ok "Full restore complete! Start Chrome to verify."
    write_log "Full restore complete"
}

start_session_restore() {
    write_header "Session Restore"

    select_backup_file "Session"
    if [ $? -ne 0 ] || [ -z "$selected_zip_file" ]; then
        write_err "No Session backup files found in: $backup_dir"
        return 1
    fi

    local zip_mb=$(du -mh "$selected_zip_file" | cut -f1)
    write_info "Backup file: $(basename "$selected_zip_file")"
    write_info "Backup size: $zip_mb"

    if ! select_restore_profiles "$selected_zip_file"; then
        write_warn "Restore cancelled."
        return 1
    fi

    local is_all=true
    if [ ${#selected_restore_folders[@]} -gt 0 ]; then
        is_all=false
        write_info "Selected profile(s) to restore:"
        for f in "${selected_restore_folders[@]}"; do
            write_color "     - $f" "DarkGray"
        done
    else
        write_info "Restoring all profiles."
    fi

    echo
    write_color "  +-------------------------------------------------------------+" "Cyan"
    write_color "  |  PORTABILITY & RESTORE PREVIEW                              |" "Cyan"
    write_color "  |   [OK] MetaMask vault and settings WILL be restored         |" "Green"
    write_color "  |   [i]  Note: Enter your normal MetaMask password to unlock  |" "Cyan"
    write_color "  +-------------------------------------------------------------+" "Cyan"
    echo

    read -r -p "  Type YES to confirm restore: " confirm
    if [ "${confirm^^}" != "YES" ]; then
        write_warn "Restore cancelled by user."
        return 1
    fi

    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    close_chrome

    if [ "$is_all" = true ]; then
        write_info "Extracting backup..."
        unzip -oq "$selected_zip_file" -d "$temp_dir"
    else
        local unzip_args=()
        for folder in "${selected_restore_folders[@]}"; do
            unzip_args+=("$folder/*")
        done
        unzip_args+=("Local State")
        write_info "Extracting selected profile(s)..."
        unzip -oq "$selected_zip_file" "${unzip_args[@]}" -d "$temp_dir"
    fi

    write_info "Merging session data into Chrome..."
    cp -a "$temp_dir/." "$chrome_profile/" 2>/dev/null
    rm -rf "$temp_dir"

    # Cookie Import Hook
    local cookie_backup_dir="$backup_dir/cookies"
    if [ -d "$cookie_backup_dir" ]; then
        mapfile -t cookie_files < <(find "$cookie_backup_dir" -name "cookies_*.json")
        if [ ${#cookie_files[@]} -gt 0 ]; then
            local matched_cookies=()
            for cf in "${cookie_files[@]}"; do
                local fname=$(basename "$cf")
                local p_folder="${fname#cookies_}"
                p_folder="${p_folder%.json}"
                if [ "$is_all" = true ] || [[ " ${selected_restore_folders[*]} " =~ " ${p_folder} " ]]; then
                    matched_cookies+=("$cf")
                fi
            done

            if [ ${#matched_cookies[@]} -gt 0 ]; then
                echo
                read -r -p "  Found backed up login sessions (cookies) for selected profile(s). Do you want to automatically import them? (YES/NO): " import_cookies
                if [ "${import_cookies^^}" == "YES" ]; then
                    close_chrome
                    for cf in "${matched_cookies[@]}"; do
                        local fname=$(basename "$cf")
                        local p_folder="${fname#cookies_}"
                        p_folder="${p_folder%.json}"
                        invoke_cookie_migration "IMPORT" "$p_folder" "$cf"
                    done
                fi
            fi
        fi
    fi

    write_ok "Session restore complete! Start Chrome to verify."
    write_log "Session restore complete"
}

# --- BACKUP INFO --------------------------------------------------------------
show_backup_info() {
    write_section "Existing Backups"
    local found=false

    mapfile -t files < <(find "$backup_dir" -maxdepth 1 -name "chrome_*.zip" -type f | sort)
    for f in "${files[@]}"; do
        [ -z "$f" ] && continue
        local fname=$(basename "$f")
        local fsize=$(du -mh "$f" | cut -f1)
        local fdate=$(date -r "$f" "+%Y-%m-%d %H:%M:%S")
        write_ok "Backup: $(printf "%-40s" "$fname") Size: $(printf "%-10s" "$fsize") Created: $fdate"
        found=true
    done

    if [ "$found" = false ]; then
        write_info "No backups found in: $backup_dir"
    fi
}

show_migration_notice() {
    echo
    write_color "  +----------------------------------------------------------------------+" "Cyan"
    write_color "  |  [OK] PORTABILITY & MIGRATION READY                                  |" "Green"
    write_color "  +----------------------------------------------------------------------+" "Cyan"
    write_color "  |                                                                      |" "DarkCyan"
    write_color "  |  [OK] MetaMask & Extensions --- Fully Portable (Ready / Backed Up)   |" "Green"
    write_color "  |  [OK] Bookmarks & Settings --- Fully Portable (Ready / Backed Up)    |" "Green"
    write_color "  |  [OK] Browser History -------- Fully Portable (Ready / Backed Up)    |" "Green"
    write_color "  |  [OK] Local Storage Data ----- Fully Portable (Ready / Backed Up)    |" "Green"
    write_color "  |                                                                      |" "DarkCyan"
    write_color "  |  [i] Note on Cookies & Passwords:                                    |" "Cyan"
    write_color "  |      These items are bound to OS security (GNOME Keyring/KWallet).   |" "Cyan"
    write_color "  |      If migrating OS, please use cookie export for session sync.     |" "Cyan"
    write_color "  +----------------------------------------------------------------------+" "Cyan"
    echo
}

# --- MAIN MENU ----------------------------------------------------------------
show_main_menu() {
    while true; do
        clear
        write_header "Chrome Backup & Restore Tool  v3.1 (Auto-Cookie Sync)"

        show_migration_notice
        show_backup_info

        write_section "Menu"
        write_color "  [1]  Backup Chrome - Full  (entire User Data folder)" "Cyan"
        write_color "  [2]  Backup Chrome - Session Only  (extensions, cookies*, data)" "Cyan"
        write_color "  [3]  Restore Chrome - Full" "Cyan"
        write_color "  [4]  Restore Chrome - Session Only" "Cyan"
        write_color "  [5]  Run System Validation" "Cyan"
        write_color "  [Q]  Quit" "DarkGray"
        echo
        write_color "  * Cookies survive cross-OS sync ONLY via Auto-Cookie Sync export/import." "DarkGray"
        echo

        read -r -p "  Enter choice: " choice
        [ -z "$choice" ] && exit 0
        
        case "${choice^^}" in
            1)
                clear
                write_header "Full Backup"
                if test_prerequisites; then
                    start_full_backup
                else
                    write_info "System validation checks failed."
                fi
                echo
                read -r -p "  Press Enter to return to menu... "
                ;;
            2)
                clear
                write_header "Session Backup"
                if test_prerequisites; then
                    start_session_backup
                fi
                echo
                read -r -p "  Press Enter to return to menu... "
                ;;
            3)
                clear
                write_header "Full Restore"
                start_full_restore
                echo
                read -r -p "  Press Enter to return to menu... "
                ;;
            4)
                clear
                write_header "Session Restore"
                start_session_restore
                echo
                read -r -p "  Press Enter to return to menu... "
                ;;
            5)
                clear
                write_header "System Validation"
                test_prerequisites
                echo
                read -r -p "  Press Enter to return to menu... "
                ;;
            Q|QUIT|EXIT)
                write_color "\n  Goodbye!\n" "Green"
                exit 0
                ;;
            * )
                write_info "Invalid choice. Please enter 1-5 or Q."
                sleep 1
                ;;
        esac
    done
}

# --- ENTRY POINT --------------------------------------------------------------
initialize_log
show_main_menu
