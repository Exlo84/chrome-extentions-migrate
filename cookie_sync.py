#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
import subprocess
import hashlib
import time

# Check for required cryptography package
try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    from cryptography.hazmat.primitives import hashes
except ImportError:
    print("Error: The 'cryptography' python library is required. Install it using: pip install cryptography")
    sys.exit(1)

def get_chrome_password():
    try:
        res = subprocess.run(["secret-tool", "lookup", "application", "chrome"], capture_output=True, text=True, check=True)
        pwd = res.stdout.strip()
        if pwd:
            return pwd
    except Exception:
        pass
    # Fallback to Chromium default password
    return "peanuts"

def derive_key(password):
    password_bytes = password.encode("utf-8")
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA1(),
        length=16,
        salt=b"saltysalt",
        iterations=1
    )
    return kdf.derive(password_bytes)

def decrypt_cookie(encrypted_val, key):
    if not encrypted_val:
        return ""
    prefix = encrypted_val[:3]
    if prefix not in (b"v10", b"v11"):
        return encrypted_val.decode("utf-8", errors="ignore")
    
    # Linux Chrome uses a hardcoded IV of 16 spaces
    iv = b" " * 16
    ciphertext = encrypted_val[3:]
    
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    decryptor = cipher.decryptor()
    decrypted = decryptor.update(ciphertext) + decryptor.finalize()
    
    # Strip PKCS#7 padding
    pad_len = decrypted[-1]
    if isinstance(pad_len, int) and 0 < pad_len <= 16:
        decrypted = decrypted[:-pad_len]
        
    # The first 32 bytes are the SHA-256 hash of the host_key (domain)
    cookie_val = decrypted[32:]
    return cookie_val.decode("utf-8", errors="ignore")

def encrypt_cookie_cbc(cookie_val, key, host_key):
    # The plaintext consists of the 32-byte SHA-256 hash of host_key, followed by the cookie value
    sig_bytes = hashlib.sha256(host_key.encode("utf-8")).digest()
    plaintext = sig_bytes + cookie_val.encode("utf-8")
    
    # Standard PKCS#7 padding
    pad_len = 16 - (len(plaintext) % 16)
    plaintext += bytes([pad_len]) * pad_len
    
    # 16-space IV
    iv = b" " * 16
    
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(plaintext) + encryptor.finalize()
    
    return b"v11" + ciphertext

def locate_database(chrome_profile_base_dir, profile_name):
    # Modern path
    db_path = os.path.join(chrome_profile_base_dir, profile_name, "Network", "Cookies")
    if os.path.exists(db_path):
        return db_path
    # Legacy path
    db_path = os.path.join(chrome_profile_base_dir, profile_name, "Cookies")
    if os.path.exists(db_path):
        return db_path
    return None

def to_str(val):
    if val is None:
        return ""
    if isinstance(val, bytes):
        return val.decode("utf-8", errors="ignore")
    return str(val)

def row_to_chrome_cookie(row_dict, key):
    # Decrypt the encrypted_value
    decrypted_value = ""
    enc_val = row_dict.get("encrypted_value")
    if enc_val:
        decrypted_value = decrypt_cookie(enc_val, key)
    else:
        decrypted_value = to_str(row_dict.get("value", ""))
        
    cookie = {
        "name": to_str(row_dict.get("name", "")),
        "value": decrypted_value,
        "domain": to_str(row_dict.get("host_key", "")),
        "path": to_str(row_dict.get("path", "")),
        "secure": bool(row_dict.get("is_secure", 0)),
        "httpOnly": bool(row_dict.get("is_httponly", 0)),
        "session": not bool(row_dict.get("is_persistent", 1)),
    }
    
    # Expiration date (convert microseconds FILETIME to unix epoch seconds)
    expires_utc = row_dict.get("expires_utc", 0)
    has_expires = row_dict.get("has_expires", 0)
    if has_expires and expires_utc > 0:
        # FILETIME epoch is 1601-01-01. Unix epoch is 1970-01-01.
        # Difference is 11644473600 seconds.
        epoch_seconds = (expires_utc / 1000000.0) - 11644473600
        cookie["expirationDate"] = epoch_seconds
        
    # SameSite mapping
    samesite_val = row_dict.get("samesite", 0)
    if samesite_val == 1:
        cookie["sameSite"] = "lax"
    elif samesite_val == 2:
        cookie["sameSite"] = "strict"
    elif samesite_val == 3:
        cookie["sameSite"] = "no_restriction"
    else:
        cookie["sameSite"] = "unspecified"
        
    cookie["storeId"] = "0"
    return cookie

def chrome_cookie_to_row(cookie, key, db_cols):
    host_key = to_str(cookie.get("domain") or cookie.get("host_key") or "")
    name = to_str(cookie.get("name", ""))
    path = to_str(cookie.get("path", ""))
    
    # Encrypt the plaintext value
    plaintext_value = to_str(cookie.get("value", ""))
    encrypted_value = encrypt_cookie_cbc(plaintext_value, key, host_key)
    
    # Get current time in microsecond FILETIME
    now_utc = int((time.time() + 11644473600) * 1000000)
    
    # Expiration Date
    expiration_date = cookie.get("expirationDate")
    if expiration_date is not None:
        expires_utc = int((float(expiration_date) + 11644473600) * 1000000)
        has_expires = 1
        is_persistent = 1
    else:
        # Session cookie fallback
        expires_utc = 0
        has_expires = 0
        is_persistent = 0
        
    # SameSite mapping
    samesite_str = to_str(cookie.get("sameSite", "unspecified")).lower()
    if samesite_str == "lax":
        samesite = 1
    elif samesite_str == "strict":
        samesite = 2
    elif samesite_str in ("no_restriction", "none"):
        samesite = 3
    else:
        samesite = 0
        
    row = {
        "creation_utc": now_utc,
        "host_key": host_key,
        "top_frame_site_key": "",
        "name": name,
        "value": "",
        "encrypted_value": encrypted_value,
        "path": path,
        "expires_utc": expires_utc,
        "is_secure": 1 if cookie.get("secure") else 0,
        "is_httponly": 1 if cookie.get("httpOnly") else 0,
        "last_access_utc": now_utc,
        "has_expires": has_expires,
        "is_persistent": is_persistent,
        "priority": 1,  # Medium
        "samesite": samesite,
        "source_scheme": 2 if cookie.get("secure") else 1,
        "source_port": 443 if cookie.get("secure") else 80,
        "last_update_utc": now_utc,
        "source_type": 1,
        "has_cross_site_ancestor": 0,
    }
    
    # Only keep columns that actually exist in the target database
    filtered_row = {}
    for col in db_cols:
        if col in row:
            filtered_row[col] = row[col]
        else:
            filtered_row[col] = 0
            
    return filtered_row

def export_cookies(db_path, key, json_path):
    if not os.path.exists(db_path):
        print(f"Error: Cookies database not found at {db_path}")
        sys.exit(1)
        
    # Copy database to a temp location to avoid database locking/WAL errors
    temp_db_path = db_path + ".temp_export"
    try:
        import shutil
        shutil.copyfile(db_path, temp_db_path)
    except Exception as e:
        print(f"Error copying database for export: {e}")
        sys.exit(1)

    conn = sqlite3.connect(temp_db_path)
    conn.text_factory = bytes  # Return TEXT columns as bytes to bypass decoding errors
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT * FROM cookies")
        rows = cursor.fetchall()
        col_names = [d[0] for d in cursor.description]
    except Exception as e:
        print(f"Error querying cookies table: {e}")
        conn.close()
        if os.path.exists(temp_db_path):
            os.remove(temp_db_path)
        sys.exit(1)
        
    cookies_list = []
    success_count = 0
    fail_count = 0
    
    for row in rows:
        row_dict = dict(zip(col_names, row))
        try:
            chrome_cookie = row_to_chrome_cookie(row_dict, key)
            cookies_list.append(chrome_cookie)
            success_count += 1
        except Exception as e:
            fail_count += 1
            
    conn.close()
    if os.path.exists(temp_db_path):
        os.remove(temp_db_path)
        
    # Write to JSON
    try:
        out_dir = os.path.dirname(os.path.abspath(json_path))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
            
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(cookies_list, f, indent=2)
        print(f"Successfully exported {success_count} cookies (failed: {fail_count}) to {json_path}")
    except Exception as e:
        print(f"Error writing JSON file: {e}")
        sys.exit(1)

def import_cookies(db_path, key, json_path):
    if not os.path.exists(db_path):
        print(f"Error: Cookies database not found at {db_path}. Profile must be restored/initialized first.")
        sys.exit(1)
        
    if not os.path.exists(json_path):
        print(f"Error: JSON backup file not found at {json_path}")
        sys.exit(1)
        
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            cookies_list = json.load(f)
    except Exception as e:
        print(f"Error reading JSON backup file: {e}")
        sys.exit(1)

    # Copy database to a temp location during import
    temp_db_path = db_path + ".temp_import"
    try:
        import shutil
        shutil.copyfile(db_path, temp_db_path)
    except Exception as e:
        print(f"Error copying database for import: {e}")
        sys.exit(1)

    conn = sqlite3.connect(temp_db_path)
    cursor = conn.cursor()
    
    try:
        cursor.execute("PRAGMA table_info(cookies)")
        db_cols = {row[1] for row in cursor.fetchall()}
    except Exception as e:
        print(f"Error reading cookies table info: {e}")
        conn.close()
        if os.path.exists(temp_db_path):
            os.remove(temp_db_path)
        sys.exit(1)

    success_count = 0
    fail_count = 0
    
    for cookie in cookies_list:
        host_key = cookie.get("domain") or cookie.get("host_key")
        name = cookie.get("name")
        path = cookie.get("path")
        if not host_key or not name or not path:
            continue
            
        try:
            row_to_insert = chrome_cookie_to_row(cookie, key, db_cols)
        except Exception as e:
            fail_count += 1
            continue

        # Unique key variables
        top_frame_site_key = row_to_insert.get("top_frame_site_key", "")
        has_cross_site_ancestor = row_to_insert.get("has_cross_site_ancestor", 0)
        source_scheme = row_to_insert.get("source_scheme", 1)
        source_port = row_to_insert.get("source_port", 80)
        
        # Delete duplicate
        try:
            cursor.execute("""
                DELETE FROM cookies 
                WHERE host_key = ? 
                  AND top_frame_site_key = ? 
                  AND has_cross_site_ancestor = ? 
                  AND name = ? 
                  AND path = ? 
                  AND source_scheme = ? 
                  AND source_port = ?
            """, (host_key, top_frame_site_key, has_cross_site_ancestor, name, path, source_scheme, source_port))
        except Exception:
            try:
                cursor.execute("DELETE FROM cookies WHERE host_key = ? AND name = ? AND path = ?", (host_key, name, path))
            except Exception:
                pass

        # Insert
        cols = ", ".join(row_to_insert.keys())
        placeholders = ", ".join(["?"] * len(row_to_insert))
        try:
            cursor.execute(f"INSERT INTO cookies ({cols}) VALUES ({placeholders})", list(row_to_insert.values()))
            success_count += 1
        except Exception as e:
            fail_count += 1
            
    conn.commit()
    conn.close()
    
    # Safely replace the database file with the imported database file
    try:
        shutil.move(temp_db_path, db_path)
        print(f"Successfully imported {success_count} cookies (failed: {fail_count}) to {db_path}")
    except Exception as e:
        print(f"Error replacing original database with imported database: {e}")
        if os.path.exists(temp_db_path):
            os.remove(temp_db_path)
        sys.exit(1)

def main():
    if len(sys.argv) < 5:
        print("Usage: cookie_sync.py <EXPORT|IMPORT> <chrome_profile_base_dir> <profile_name> <json_path>")
        sys.exit(1)
        
    mode = sys.argv[1].upper()
    chrome_profile_base_dir = sys.argv[2]
    profile_name = sys.argv[3]
    json_path = sys.argv[4]
    
    if mode not in ("EXPORT", "IMPORT"):
        print(f"Error: Unknown mode '{mode}'. Must be EXPORT or IMPORT.")
        sys.exit(1)
        
    db_path = locate_database(chrome_profile_base_dir, profile_name)
    if not db_path:
        db_path = os.path.join(chrome_profile_base_dir, profile_name, "Network", "Cookies")
        print(f"Error: Cookies database not found for profile '{profile_name}' in '{chrome_profile_base_dir}'")
        sys.exit(1)
        
    pwd = get_chrome_password()
    key = derive_key(pwd)
    
    if mode == "EXPORT":
        export_cookies(db_path, key, json_path)
    elif mode == "IMPORT":
        import_cookies(db_path, key, json_path)

if __name__ == "__main__":
    main()
