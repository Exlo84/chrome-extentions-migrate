Copy Chrome Extensions from Windows to Ubuntu
=============================================

This script facilitates the transfer of Google Chrome extensions from a Windows installation to Ubuntu. It's particularly useful for users who dual-boot Windows and Ubuntu and wish to have their Chrome extensions, including settings and local data, synchronized between both operating systems.

Warning
-------

Before proceeding, please be aware that this script directly manipulates files in the Chrome user data directory. It is strongly recommended to:

-   Close Chrome on Ubuntu before running the script to prevent any conflicts.
-   Backup your Chrome user data directory in both Windows and Ubuntu.
-   Understand that while this script has been made with care, its use is at your own risk. The creators of this script cannot be held responsible for any data loss or other issues.

Prerequisites
-------------

-   A dual-boot setup with Windows and Ubuntu.
-   Google Chrome installed on both Windows and Ubuntu.
-   The Windows partition must be mounted in Ubuntu.
-   Basic familiarity with the terminal and executing bash scripts.

Usage
-----

1.  Prepare the Script:

    -   Download or create the `copy_chrome_extensions.sh` script on your Ubuntu system.
    -   Open your terminal and navigate to the directory containing the script.
2.  Make the Script Executable:

    `chmod +x copy_chrome_extensions.sh`

3.  Execute the Script:

    `./copy_chrome_extensions.sh`

4.  Follow On-Screen Instructions:

    -   The script will automatically backup existing Chrome extension data in Ubuntu and then copy the Chrome extension data from Windows to Ubuntu.
    -   Pay close attention to any messages or warnings displayed by the script.
5.  Restart Chrome on Ubuntu to apply the changes.

Customization
-------------

If your Chrome installation directories differ from the defaults, or if you wish to copy additional directories, you can modify the `DIRS_TO_COPY` array within the script:

`DIRS_TO_COPY=("Extensions" "Local Extension Settings" "Local Storage" "Extension State")`

Add or remove directories as needed, ensuring they are relative to the Chrome user data directory.

MetaMask
-------------
To successfully copy MetaMask, with wallets and networks, you have to uninstall on Linux first, run the script, and then install MetaMask again

Contributing
------------

Contributions to improve the script or documentation are welcome. Please feel free to fork the repository, make your changes, and submit a pull request.
