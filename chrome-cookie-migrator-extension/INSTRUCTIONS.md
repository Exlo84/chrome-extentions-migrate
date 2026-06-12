# Chrome Cookie Migrator — Setup & Instructions

This custom extension allows you to manually export your login session cookies as a JSON file, or import cookies (such as those created by the automated backup scripts) back into Google Chrome. This bypasses the Windows DPAPI/App-Bound Encryption limits when moving accounts to another profile or machine.

---

## 1. How to Install the Extension in Chrome

Since this is a custom tool, you must load it into Chrome manually using **Developer Mode**:

1. Open **Google Chrome**.
2. In the URL bar, go to: **`chrome://extensions/`**
3. In the top-right corner of the Extensions page, toggle the **Developer mode** switch to **ON**.
4. In the top-left corner, click the **Load unpacked** button.
5. In the file dialog that opens, select the folder:
   `c:\Users\exlo\OneDrive\Documents\GitHub\chrome-extentions-migrate-v2\chrome-cookie-migrator-extension`
6. Click **Select Folder**.

The **Chrome Cookie Migrator** card will now appear in your list of extensions!

---

## 2. How to Use the Extension

Click the **Extensions puzzle piece** icon in Chrome's top-right toolbar, find **Chrome Cookie Migrator**, and pin it. Click its icon to open the window:

### Tab A: Export (Backup Sessions)
1. In the **Export** tab, search/filter domains if you only want to save specific sessions (e.g. `github.com`), or leave it empty to select everything.
2. Click **Download Cookies JSON**.
3. Choose where to save the file.

### Tab B: Import (Restore Sessions)
1. Click the **Import** tab.
2. Drag and drop any cookie backup JSON file into the dotted zone, or click **Browse File** to locate one.
   * *Tip:* You can find your automated backup JSON files under `backup/cookies/` (e.g. `cookies_Default.json`).
3. View the preview details (filename, size, number of cookies, and domains) to confirm it is the correct file.
4. Click **Confirm Import**.
5. Wait for the injection progress bar to complete (usually takes 1–3 seconds).
6. Refresh any website tabs you were logged out of. You should now be logged back in automatically!
