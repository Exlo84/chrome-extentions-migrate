Chrome Extension and Session Backup and Restore Scripts
=======================================================

This repository contains scripts to back up and restore both Chrome extensions and session data. It supports both **Windows** and **Ubuntu** systems. You can use these scripts to transfer your Chrome profile, including extensions and login sessions, between systems, or as a backup to avoid logging back into accounts after restoring.

Features
--------

-   **Backup and restore Chrome extensions** and profile data (including extensions, settings, and more).
-   **Backup and restore session data** (cookies, saved logins, session state) to preserve your active sessions without logging back in.
-   **Cross-platform support**: Scripts for both Windows and Ubuntu.
-   **Exclude non-essential files** like cache, media, and browsing history to keep the backup small.

Files in the Repository
-----------------------

-   `backup_sessions.bat`: Backup Chrome session data (Windows).
-   `restore_sessions.bat`: Restore Chrome session data (Windows).
-   `restore_sessions.sh`: Restore Chrome session data (Ubuntu).
-   `backup_extensions.bat`: Backup Chrome profile and extensions (Windows).
-   `restore_extensions.bat`: Restore Chrome profile and extensions (Windows).
-   `restore_extensions.sh`: Restore Chrome profile and extensions (Ubuntu).

* * * * *

Getting Started
---------------

### Prerequisites

-   **Windows**: PowerShell 5.0 or later (comes pre-installed on Windows 10).
-   **Ubuntu**: `unzip` should be installed for restoration scripts. Install using:

    bash

    Kopier kode

    `sudo apt-get install unzip`

* * * * *

Backup Instructions
-------------------

### Windows (Backup Chrome Profile and Extensions)

1.  Download or clone this repository to your machine.
2.  Run the `backup_extensions.bat` script by double-clicking it or from a command prompt.
    -   The script will back up your entire Chrome profile, including extensions, to a `backup` folder in the same directory.
    -   A `chrome_backup.zip` file will be created in the `backup` folder.

bash

Kopier kode

`backup_extensions.bat`

### Windows (Backup Chrome Session Data Only)

1.  Download or clone this repository to your machine.
2.  Run the `backup_sessions.bat` script by double-clicking it or from a command prompt.
    -   This script will back up only your essential session data, excluding non-essential items like cache.
    -   A `session_backup.zip` file will be created in the `backup` folder.

bash

Kopier kode

`backup_sessions.bat`

* * * * *

Restore Instructions
--------------------

### Windows (Restore Chrome Profile and Extensions)

1.  Ensure you have a `chrome_backup.zip` file in the `backup` folder.
2.  Run the `restore_extensions.bat` script by double-clicking it or from a command prompt.
    -   The script will restore your Chrome profile, including extensions, to its proper location.

bash

Kopier kode

`restore_extensions.bat`

### Windows (Restore Chrome Session Data Only)

1.  Ensure you have a `session_backup.zip` file in the `backup` folder.
2.  Run the `restore_sessions.bat` script by double-clicking it or from a command prompt.
    -   The script will restore your session data, allowing you to pick up where you left off without having to log in again.

bash

Kopier kode

`restore_sessions.bat`

### Ubuntu (Restore Chrome Profile and Extensions)

1.  Ensure you have a `chrome_backup.zip` file in the `backup` folder.
2.  Open a terminal, navigate to the folder containing the `restore_extensions.sh` script, and run:

bash

Kopier kode

`./restore_extensions.sh`

-   The script will restore your Chrome profile, including extensions, to its proper location.

### Ubuntu (Restore Chrome Session Data Only)

1.  Ensure you have a `session_backup.zip` file in the `backup` folder.
2.  Open a terminal, navigate to the folder containing the `restore_sessions.sh` script, and run:

bash

Kopier kode

`./restore_sessions.sh`

-   The script will restore your session data, allowing you to continue browsing without having to log back into your accounts.

* * * * *

Excluded Files
--------------

To keep the backups lightweight, these scripts exclude non-essential files such as:

-   **`Cache/`**: Temporary cached files (recreated by Chrome).
-   **`GPUCache/`**: GPU processing cache.
-   **`Application Cache/`**: Web app cache.
-   **`Media Cache/`**: Media content cache.

These files will be automatically recreated by Chrome when needed and are not necessary for session or extension restoration.

* * * * *

Backup File Structure
---------------------

After running the backup scripts, your backup folder will contain:

-   **`chrome_backup.zip`** (for full Chrome profile, including extensions).
-   **`session_backup.zip`** (for session data only).
-   The backups will include essential files such as `Cookies`, `Login Data`, `Preferences`, and `Sessions` (for session restoration), or the entire `User Data` folder (for profile and extension backup).

* * * * *

Important Notes
---------------

-   The restore scripts **overwrite** any existing Chrome profile or session data, so be careful when restoring.
-   Session backup scripts only back up data related to current sessions, such as login cookies and active windows. They do not include history, bookmarks, or extensions.

* * * * *

License
-------

This project is licensed under the MIT License. See the LICENSE file for more details.

* * * * *

Contributing
------------

Feel free to submit issues or pull requests to improve these scripts!