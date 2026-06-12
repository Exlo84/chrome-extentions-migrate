// UI States and Handlers for Cookie Migrator

document.addEventListener('DOMContentLoaded', () => {
  // Navigation elements
  const tabExport = document.getElementById('tab-export');
  const tabImport = document.getElementById('tab-import');
  const paneExport = document.getElementById('pane-export');
  const paneImport = document.getElementById('pane-import');

  // Export elements
  const exportSearch = document.getElementById('export-search');
  const exportTotalCount = document.getElementById('export-total-count');
  const exportFilteredCount = document.getElementById('export-filtered-count');
  const btnExportDownload = document.getElementById('btn-export-download');

  // Import elements
  const dropZone = document.getElementById('drop-zone');
  const fileInput = document.getElementById('file-input');
  const btnSelectFile = document.getElementById('btn-select-file');
  const importPreview = document.getElementById('import-preview');
  const previewFilename = document.getElementById('preview-filename');
  const previewSize = document.getElementById('preview-size');
  const previewCount = document.getElementById('preview-count');
  const previewDomains = document.getElementById('preview-domains');
  const btnImportConfirm = document.getElementById('btn-import-confirm');
  const btnImportCancel = document.getElementById('btn-import-cancel');

  // Progress UI
  const progressArea = document.getElementById('import-progress-area');
  const progressBarFill = document.getElementById('progress-bar-fill');
  const progressText = document.getElementById('progress-text');
  const progressPercent = document.getElementById('progress-percent');

  // Status elements
  const statusBanner = document.getElementById('status-banner');
  const statusMsg = document.getElementById('status-msg');

  // In-memory data states
  let allCookies = [];
  let filteredCookies = [];
  let importData = null;

  // Set up Status message
  function setStatus(text, type = 'info') {
    statusMsg.textContent = text;
    statusBanner.className = 'app-status';
    if (type === 'success') {
      statusBanner.classList.add('success');
    } else if (type === 'error') {
      statusBanner.classList.add('error');
    }
  }

  // --- TABS ACTION ---
  tabExport.addEventListener('click', () => {
    tabExport.classList.add('active');
    tabImport.classList.remove('active');
    paneExport.classList.add('active');
    paneImport.classList.remove('active');
    loadExportCookies();
  });

  tabImport.addEventListener('click', () => {
    tabImport.classList.add('active');
    tabExport.classList.remove('active');
    paneImport.classList.add('active');
    paneExport.classList.remove('active');
  });

  // --- EXPORT LOGIC ---
  function loadExportCookies() {
    chrome.cookies.getAll({}, (cookies) => {
      allCookies = cookies || [];
      filterAndRenderExport();
    });
  }

  function filterAndRenderExport() {
    const query = exportSearch.value.trim().toLowerCase();
    if (query) {
      filteredCookies = allCookies.filter(c => c.domain.toLowerCase().includes(query));
    } else {
      filteredCookies = allCookies;
    }

    exportTotalCount.textContent = allCookies.length;
    exportFilteredCount.textContent = filteredCookies.length;
  }

  exportSearch.addEventListener('input', filterAndRenderExport);

  btnExportDownload.addEventListener('click', () => {
    if (filteredCookies.length === 0) {
      setStatus('No cookies to download.', 'error');
      return;
    }

    // Map extension cookie fields to the syncer's expected export format
    const exportPayload = filteredCookies.map(cookie => {
      const mapped = {
        name: cookie.name || "",
        value: cookie.value || "",
        domain: cookie.domain || "",
        path: cookie.path || "/",
        secure: cookie.secure || false,
        httpOnly: cookie.httpOnly || false,
        session: cookie.session || false,
        storeId: cookie.storeId || "0"
      };
      if (cookie.expirationDate !== undefined) {
        mapped.expirationDate = cookie.expirationDate;
      }
      if (cookie.sameSite !== undefined) {
        mapped.sameSite = cookie.sameSite;
      }
      return mapped;
    });

    const jsonStr = JSON.stringify(exportPayload, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const timestamp = new Date().toISOString().replace(/T/, '_').replace(/\..+/, '').replace(/:/g, '-');
    const filename = `chrome_cookies_export_${timestamp}.json`;

    chrome.downloads.download({
      url: url,
      filename: filename,
      saveAs: true
    }, () => {
      setStatus(`Saved export to download folder.`, 'success');
    });
  });

  // --- IMPORT FILE HANDLING ---
  btnSelectFile.addEventListener('click', () => {
    fileInput.click();
  });

  fileInput.addEventListener('change', (e) => {
    handleFiles(e.target.files);
  });

  // Drop zone drag and drop handlers
  ['dragenter', 'dragover'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      dropZone.classList.add('dragover');
    }, false);
  });

  ['dragleave', 'drop'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      dropZone.classList.remove('dragover');
    }, false);
  });

  dropZone.addEventListener('drop', (e) => {
    const dt = e.dataTransfer;
    const files = dt.files;
    handleFiles(files);
  });

  function handleFiles(files) {
    if (files.length === 0) return;
    const file = files[0];
    if (file.type !== 'application/json' && !file.name.endsWith('.json')) {
      setStatus('Invalid file type. Must be a .json file.', 'error');
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const parsed = JSON.parse(e.target.result);
        if (!Array.isArray(parsed)) {
          setStatus('Invalid cookies format. Must be an array.', 'error');
          return;
        }

        importData = parsed;
        previewFileDetails(file, parsed);
      } catch (err) {
        setStatus('Error parsing JSON file.', 'error');
      }
    };
    reader.readAsText(file);
  }

  function previewFileDetails(file, data) {
    // Collect unique domains
    const domains = new Set();
    data.forEach(c => {
      if (c.domain || c.host_key) {
        domains.add(c.domain || c.host_key);
      }
    });

    previewFilename.textContent = file.name;
    previewSize.textContent = `${(file.size / 1024).toFixed(1)} KB`;
    previewCount.textContent = data.length;
    previewDomains.textContent = domains.size;

    dropZone.style.display = 'none';
    importPreview.style.display = 'block';
    progressArea.style.display = 'none';
    setStatus('Ready to import file.', 'info');
  }

  btnImportCancel.addEventListener('click', () => {
    resetImportUI();
  });

  function resetImportUI() {
    importData = null;
    fileInput.value = '';
    dropZone.style.display = 'flex';
    importPreview.style.display = 'none';
    progressArea.style.display = 'none';
    setStatus('Extension Loaded and Ready', 'info');
  }

  // --- INJECTION ENGINE ---
  btnImportConfirm.addEventListener('click', async () => {
    if (!importData || importData.length === 0) {
      setStatus('No data to import.', 'error');
      return;
    }

    importPreview.style.display = 'none';
    progressArea.style.display = 'block';
    setStatus('Injecting cookies...', 'info');

    const total = importData.length;
    let completed = 0;
    let failed = 0;

    const getCookieUrl = (cookie) => {
      let domain = cookie.domain || cookie.host_key || "";
      if (domain.startsWith('.')) {
        domain = domain.substring(1);
      }
      const secure = cookie.secure !== undefined ? cookie.secure : true;
      const protocol = secure ? 'https://' : 'http://';
      return protocol + domain + (cookie.path || '/');
    };

    // Inject batch loop
    for (const cookie of importData) {
      // Basic validation
      const name = cookie.name;
      const val = cookie.value;
      if (name === undefined || val === undefined) {
        failed++;
        completed++;
        updateProgress(completed, total);
        continue;
      }

      // Format details
      const details = {
        url: getCookieUrl(cookie),
        name: name,
        value: val,
        path: cookie.path || '/',
        secure: cookie.secure || false,
        httpOnly: cookie.httpOnly || false
      };

      if (cookie.expirationDate !== undefined) {
        // Drop expired cookies to avoid breaking site sessions
        if (cookie.expirationDate < Date.now() / 1000) {
          completed++;
          updateProgress(completed, total);
          continue;
        }
        details.expirationDate = cookie.expirationDate;
      }

      if (cookie.sameSite && cookie.sameSite !== 'unspecified') {
        details.sameSite = cookie.sameSite;
        if (cookie.sameSite === 'no_restriction') {
          details.secure = true;
        }
      }

      const domain = cookie.domain || cookie.host_key;
      if (domain && domain.startsWith('.')) {
        details.domain = domain;
      }

      // Promisified cookie set
      try {
        await new Promise((resolve) => {
          chrome.cookies.set(details, (res) => {
            if (chrome.runtime.lastError || !res) {
              failed++;
            }
            resolve();
          });
        });
      } catch (err) {
        failed++;
      }

      completed++;
      updateProgress(completed, total);
      
      // Yield processing every 15 cookies to keep the extension UI smooth
      if (completed % 15 === 0) {
        await new Promise(r => setTimeout(r, 0));
      }
    }

    setStatus(`Import completed! Success: ${total - failed - (total - completed)}, Failed/Skipped: ${failed}`, failed > 0 ? 'info' : 'success');
    
    // Add brief timeout before resetting
    setTimeout(() => {
      resetImportUI();
    }, 4000);
  });

  function updateProgress(completed, total) {
    const pct = Math.round((completed / total) * 100);
    progressBarFill.style.width = `${pct}%`;
    progressText.textContent = `${completed} / ${total}`;
    progressPercent.textContent = `${pct}%`;
  }

  // Load initial cookies
  loadExportCookies();
});
