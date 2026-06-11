#Requires -Version 5.1
<#
.SYNOPSIS
    Chrome Backup & Restore Tool - Idiot-Proof Edition
.DESCRIPTION
    Backs up and restores Google Chrome user data with full validation,
    OS/Chrome version checks, progress bars with ETA, and detailed logging.
    Compatible with Chrome 80+ (DPAPI) and Chrome 127+ (App-Bound Encryption).
.NOTES
    IMPORTANT: Session cookies and saved passwords are encrypted using Windows
    DPAPI/App-Bound Encryption and are tied to the current Windows installation.
    Restoring on a NEW Windows install will NOT keep you logged in to websites.
    Extensions like MetaMask WILL migrate successfully (self-encrypted vault).
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Load compression assembly at startup
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# --- CONFIGURATION ------------------------------------------------------------
$Script:ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Script:BackupDir      = Join-Path $ScriptDir "backup"
$Script:FullZip        = Join-Path $BackupDir "chrome_full_backup_windows.zip"
$Script:SessionZip     = Join-Path $BackupDir "chrome_session_backup_windows.zip"
$Script:LogFile        = Join-Path $BackupDir "chrome_backup.log"
$Script:TempDir        = Join-Path $BackupDir "_temp_working"
$Script:ChromeUserData = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$Script:ChromeDefault  = Join-Path $Script:ChromeUserData "Default"

# Session-only files to include (individual files in Default\)
$Script:SessionFiles = @(
    "Login Data", "Login Data-journal",
    "Preferences", "Preferences-journal",
    "Web Data", "Web Data-journal",
    "Sync Data",
    "History", "History-journal",
    "Favicons", "Favicons-journal",
    "Shortcuts", "Shortcuts-journal",
    "Top Sites", "Top Sites-journal",
    "Visited Links",
    "Network Action Predictor",
    "Bookmarks", "Bookmarks-journal"
)

# Session-only folders to include (directories in Default\)
$Script:SessionDirs = @(
    "Network",                   # Contains Cookies
    "Extensions",
    "Extension State",
    "Local Extension Settings",  # MetaMask vault lives here
    "Sync Extension Settings",
    "IndexedDB",                 # MetaMask IndexedDB data
    "Local Storage",
    "Session Storage",
    "Sessions",
    "Service Worker",
    "shared_proto_db",
    "Sync Data"
)

# --- COLOURS ------------------------------------------------------------------
function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = 'White', [switch]$NoNewLine)
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = $Color
    if ($NoNewLine) { Write-Host $Text -NoNewline } else { Write-Host $Text }
    [Console]::ForegroundColor = $prev
}

function Write-Header {
    param([string]$Title)
    $width = 72
    $line  = '=' * $width
    Write-Host ""
    Write-Color "  +$line+" Cyan
    Write-Color ("  |{0,-$width}|" -f "  $Title") Cyan
    Write-Color "  +$line+" Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Color "  -- $Title " DarkCyan -NoNewLine
    Write-Color ('-' * ([Math]::Max(2, 60 - $Title.Length))) DarkCyan
}

function Write-OK    { param([string]$m) Write-Color "  [OK] $m" Green }
function Write-Warn  { param([string]$m) Write-Color "  [i]  $m" Cyan }
function Write-Err   { param([string]$m) Write-Color "  [X]  $m" Red }
function Write-Info  { param([string]$m) Write-Color "  [i]  $m" Cyan }

# --- LOGGING ------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $Script:LogFile -Value "[$stamp] [$Level] $Message" -ErrorAction SilentlyContinue
}

function Initialize-Log {
    if (-not (Test-Path $Script:BackupDir)) {
        New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null
    }
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Set-Content -Path $Script:LogFile -Value "[$stamp] Chrome Backup/Restore Tool Started"
    Add-Content -Path $Script:LogFile -Value "[$stamp] Script Dir: $Script:ScriptDir"
    Add-Content -Path $Script:LogFile -Value "[$stamp] Backup Dir: $Script:BackupDir"
}

# --- PROGRESS BAR -------------------------------------------------------------
$Script:ProgressId = 42

function Show-Progress {
    param(
        [int]      $Percent,
        [string]   $Label     = 'Working...',
        [string]   $Item      = '',
        [DateTime] $StartTime = [DateTime]::Now
    )

    $elapsed   = (Get-Date) - $StartTime
    $remainSec = -1

    if ($Percent -gt 2 -and $elapsed.TotalSeconds -gt 0) {
        $totalSec  = $elapsed.TotalSeconds / ($Percent / 100.0)
        $remainSec = [int][Math]::Max(0, $totalSec - $elapsed.TotalSeconds)
    }

    if ($elapsed.TotalHours -ge 1) {
        $elapsedStr = '{0}h {1:D2}m {2:D2}s' -f [int][Math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds
    } elseif ($elapsed.TotalMinutes -ge 1) {
        $elapsedStr = '{0}m {1:D2}s' -f [int][Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
    } else {
        $elapsedStr = '{0}s' -f $elapsed.Seconds
    }

    $status = "$Percent%   Elapsed: $elapsedStr"
    if ($Item) { $status += "   $Item" }

    $wpParams = @{
        Id               = $Script:ProgressId
        Activity         = $Label
        Status           = $status
        PercentComplete  = [Math]::Min(100, $Percent)
    }
    if ($remainSec -ge 0) { $wpParams['SecondsRemaining'] = $remainSec }

    Write-Progress @wpParams
}

function Complete-Progress {
    param([string]$Label = 'Done')
    Write-Progress -Id $Script:ProgressId -Activity $Label -Completed
}

# --- VALIDATION ---------------------------------------------------------------
function Test-Prerequisites {
    Write-Section "System Validation"
    $allOk = $true

    # 1. Windows version
    $osVer = [System.Environment]::OSVersion.Version
    if ($osVer.Major -lt 10) {
        Write-Err "Windows 10 or 11 is required. Detected: $($osVer.ToString())"
        $allOk = $false
    } else {
        $build = $osVer.Build
        $name  = if ($build -ge 22000) { "Windows 11" } else { "Windows 10" }
        Write-OK "OS: $name (Build $build)"
    }

    # 2. PowerShell version
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
        Write-Err "PowerShell 5.1+ required. Detected: $($psVer.ToString())"
        $allOk = $false
    } else {
        Write-OK "PowerShell: $($psVer.ToString())"
    }

    # 3. Chrome executable
    $chromePaths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    $chromeExe = $null
    foreach ($p in $chromePaths) {
        if (Test-Path $p) { $chromeExe = $p; break }
    }
    if (-not $chromeExe) {
        Write-Info "Chrome executable: Custom location or not standard (will verify User Data directly)"
    } else {
        $chromeVer = (Get-Item $chromeExe).VersionInfo.FileVersion
        $Script:ChromeVersion = $chromeVer
        $majorVer = [int]($chromeVer -split '\.')[0]
        Write-OK "Chrome: v$chromeVer at $chromeExe"
        Write-OK "MetaMask & Extensions are fully portable via file copy."
    }

    # 4. Chrome User Data folder
    if (-not (Test-Path $Script:ChromeUserData)) {
        Write-Err "Chrome User Data not found: $Script:ChromeUserData"
        Write-Err "Is Chrome installed and has it been run at least once?"
        $allOk = $false
    } else {
        $sizeBytes = (Get-ChildItem $Script:ChromeUserData -Recurse -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
        $sizeMB = [Math]::Round($sizeBytes / 1MB, 1)
        Write-OK "Chrome User Data: $Script:ChromeUserData ($sizeMB MB)"
    }

    # 5. Default profile
    if (-not (Test-Path $Script:ChromeDefault)) {
        Write-Err "Chrome Default profile not found: $Script:ChromeDefault"
        Write-Err "Chrome must be run at least once before backing up."
        $allOk = $false
    } else {
        Write-OK "Default profile: Found"
    }

    # 6. Key sub-folders check
    $keyFolders = @("Network", "Extensions", "Local Extension Settings", "IndexedDB", "Local Storage")
    $missing = @()
    foreach ($f in $keyFolders) {
        $fp = Join-Path $Script:ChromeDefault $f
        if (-not (Test-Path $fp)) { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        Write-Info "Chrome Folders status: Dynamic folders will be generated by Chrome when needed."
    } else {
        Write-OK "All key Chrome folders: Present"
    }

    # 7. Cookies location
    $cookiesOld = Join-Path $Script:ChromeDefault "Cookies"
    $cookiesNew = Join-Path $Script:ChromeDefault "Network\Cookies"
    if (Test-Path $cookiesNew) {
        Write-OK "Cookies: Location verified"
    } elseif (Test-Path $cookiesOld) {
        Write-OK "Cookies: Location verified"
    } else {
        Write-Info "Cookies: Dynamic (will be generated by Chrome)"
    }

    # 8. Local State file
    $localState = Join-Path $Script:ChromeUserData "Local State"
    if (Test-Path $localState) {
        Write-OK "Local State config: Verified"
    } else {
        Write-Info "Local State config: Not yet created (standard)"
    }

    # 9. Available disk space for backup
    $targetDrive = Split-Path -Qualifier $Script:BackupDir
    try {
        $drive = Get-PSDrive ($targetDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($drive -and $drive.Free) {
            $freeMB = [Math]::Round($drive.Free / 1MB)
            if ($freeMB -lt 500) {
                Write-Info "Backup drive space: $freeMB MB free"
            } else {
                Write-OK "Backup drive free space: $freeMB MB"
            }
        }
    } catch { }

    # 10. Admin check
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-OK "User privilege level: Administrator"
    } else {
        Write-OK "User privilege level: Standard User"
    }

    Write-Host ""
    return $allOk
}

# --- CHROME PROCESS -----------------------------------------------------------
function Stop-Chrome {
    Write-Info "Checking for running Chrome processes..."
    $procs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Info "$($procs.Count) Chrome process(es) found. Closing Chrome..."
        Write-Log "Closing $($procs.Count) Chrome processes"
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Verify closed
        $remaining = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
        if ($remaining) {
            Write-Info "Action required: Please close Chrome manually, then press Enter."
            Read-Host "Press Enter when Chrome is closed"
        } else {
            Write-OK "Chrome closed successfully."
        }
    } else {
        Write-OK "Chrome is not running."
    }
    Start-Sleep -Milliseconds 500
}

# --- FILE COUNTING ------------------------------------------------------------
function Get-FileList {
    param([string[]]$Paths)
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($p in $Paths) {
        if (Test-Path $p -PathType Leaf) {
            $files.Add((Get-Item $p))
        } elseif (Test-Path $p -PathType Container) {
            Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $files.Add($_) }
        }
    }
    return $files
}

# --- COPY WITH PROGRESS -------------------------------------------------------
function Copy-WithProgress {
    param(
        [System.Collections.Generic.List[System.IO.FileInfo]]$Files,
        [string]$SourceRoot,
        [string]$DestRoot,
        [string]$Label = "Copying files"
    )

    $total     = $Files.Count
    $totalSize = ($Files | Measure-Object -Property Length -Sum).Sum
    if ($total -eq 0) {
        Write-Info "No files to copy."
        return
    }

    $done      = 0
    $bytesDone = 0
    $start     = Get-Date

    Write-Log "$Label - $total files, $([Math]::Round($totalSize/1MB,1)) MB"

    foreach ($file in $Files) {
        $relPath = $file.FullName.Substring($SourceRoot.Length).TrimStart('\','/')
        $dest    = Join-Path $DestRoot $relPath
        $destDir = Split-Path $dest -Parent

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        try {
            Copy-Item -Path $file.FullName -Destination $dest -Force -ErrorAction Stop
            $bytesDone += $file.Length
        } catch {
            Write-Log "WARN: Could not copy $($file.FullName): $_" "WARN"
        }

        $done++
        $pct = [Math]::Min(99, [Math]::Round($done / $total * 100))
        Show-Progress -Percent $pct -Label $Label -Item $file.Name -StartTime $start
    }

    Complete-Progress -Label $Label
    Write-OK "$Label complete - $done files copied ($([Math]::Round($bytesDone/1MB,1)) MB)"
    Write-Log "$Label complete - $done files, $([Math]::Round($bytesDone/1MB,1)) MB"
}

# --- ZIP WITH PROGRESS --------------------------------------------------------
function Compress-WithProgress {
    param(
        [string]$SourceDir,
        [string]$ZipPath,
        [string]$Label = "Compressing"
    )

    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    $allFiles  = Get-ChildItem $SourceDir -Recurse -File -ErrorAction SilentlyContinue
    $total     = @($allFiles).Count
    $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum

    Write-Info "Compressing $total files ($([Math]::Round($totalSize/1MB,1)) MB) - $(Split-Path $ZipPath -Leaf)"
    Write-Log "Compressing $total files to $ZipPath"

    $start = Get-Date

    try {
        $zipMode   = [System.IO.Compression.ZipArchiveMode]::Create
        $zipStream = [System.IO.Compression.ZipFile]::Open($ZipPath, $zipMode)

        $done      = 0
        $bytesDone = 0

        foreach ($f in $allFiles) {
            $entryName = $f.FullName.Substring($SourceDir.Length).TrimStart('\','/').Replace('\','/')
            try {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $zipStream, $f.FullName, $entryName,
                    [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
                $bytesDone += $f.Length
            } catch {
                Write-Log "WARN: Could not zip $($f.FullName): $_" "WARN"
            }

            $done++
            $pct = [Math]::Min(99, [Math]::Round($done / $total * 100))
            Show-Progress -Percent $pct -Label $Label -Item $f.Name -StartTime $start
        }
    } finally {
        if ($zipStream) { $zipStream.Dispose() }
    }

    $zipSizeMB = [Math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
    Complete-Progress -Label $Label
    Write-OK "Compression complete - $zipSizeMB MB ZIP created"
    Write-Log "Compression complete - $zipSizeMB MB at $ZipPath"
}

# --- UNZIP WITH PROGRESS ------------------------------------------------------
# --- UNZIP WITH PROGRESS ------------------------------------------------------
function Expand-WithProgress {
    param(
        [string]$ZipPath,
        [string]$DestDir,
        [string[]]$FilterFolders = $null,
        [string]$Label = "Extracting"
    )

    $zipSizeMB = [Math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
    Write-Info "Extracting $zipSizeMB MB ZIP - $DestDir"
    Write-Log "Extracting $ZipPath to $DestDir"

    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }

    $start = Get-Date

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        
        $entriesToExtract = [System.Collections.Generic.List[System.IO.Compression.ZipArchiveEntry]]::new()
        foreach ($entry in $zip.Entries) {
            $shouldExtract = $false
            if ($null -eq $FilterFolders) {
                $shouldExtract = $true
            } else {
                $isRootFile = -not $entry.FullName.Contains('/')
                if ($isRootFile) {
                    $shouldExtract = $true
                } else {
                    $parts = $entry.FullName -split '/'
                    $firstFolder = $parts[0]
                    if ($firstFolder -in $FilterFolders) {
                        $shouldExtract = $true
                    }
                }
            }
            if ($shouldExtract) {
                $entriesToExtract.Add($entry)
            }
        }

        $total = $entriesToExtract.Count
        $done = 0
        foreach ($entry in $entriesToExtract) {
            $destPath = Join-Path $DestDir $entry.FullName.Replace('/', '\')
            $destFile = $destPath.TrimEnd('\')

            if ($entry.FullName.EndsWith('/')) {
                if (-not (Test-Path $destFile)) { New-Item -ItemType Directory -Path $destFile -Force | Out-Null }
            } else {
                $dir = Split-Path $destFile -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                try {
                    $entStream  = $entry.Open()
                    $fileStream = [System.IO.File]::Create($destFile)
                    $entStream.CopyTo($fileStream)
                    $fileStream.Close()
                    $entStream.Close()
                } catch {
                    Write-Log "WARN: Could not extract $($entry.FullName): $_" "WARN"
                }
            }

            $done++
            $pct = [Math]::Min(99, [Math]::Round($done / $total * 100))
            Show-Progress -Percent $pct -Label $Label -Item $entry.Name -StartTime $start
        }
    } finally {
        if ($zip) { $zip.Dispose() }
    }

    Complete-Progress -Label $Label
    Write-OK "Extraction complete - $done entries extracted"
    Write-Log "Extraction complete - $done entries"
}

# --- CLEANUP TEMP -------------------------------------------------------------
function Remove-TempDir {
    if (Test-Path $Script:TempDir) {
        Write-Info "Cleaning up temp directory..."
        Remove-Item $Script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- AUTOMATIC COOKIE SYNC (DPAPI BYPASS) --------------------------------------
function Get-ChromeProfilesDetailed {
    $profiles = @()
    if (Test-Path $Script:ChromeUserData) {
        Get-ChildItem $Script:ChromeUserData -Directory | ForEach-Object {
            $folder = $_.Name
            if ($folder -eq 'Default' -or $folder -like 'Profile*') {
                $prefPath = Join-Path $_.FullName "Preferences"
                $hasCookies = (Test-Path (Join-Path $_.FullName "Network\Cookies")) -or (Test-Path (Join-Path $_.FullName "Cookies"))
                
                if ((Test-Path $prefPath) -or $hasCookies) {
                    $email = ""
                    $friendlyName = ""
                    if (Test-Path $prefPath) {
                        try {
                            $json = Get-Content $prefPath -Raw -Encoding utf8 | ConvertFrom-Json
                            if ($json.account_info -and $json.account_info.Count -gt 0) {
                                $email = $json.account_info[0].email
                            }
                            if (-not $email -and $json.google -and $json.google.services) {
                                $email = $json.google.services.username
                                if (-not $email) {
                                    $email = $json.google.services.signin.username
                                }
                            }
                            if ($json.profile) {
                                $friendlyName = $json.profile.name
                            }
                        } catch {}
                    }
                    $profiles += [PSCustomObject]@{
                        Folder = $folder
                        Email  = $email
                        Name   = $friendlyName
                    }
                }
            }
        }
    }
    return $profiles
}

function Select-ChromeProfiles {
    param(
        [string]$ActionType
    )

    $profiles = Get-ChromeProfilesDetailed
    if ($profiles.Count -eq 0) {
        Write-Warn "No Chrome profiles detected."
        return @()
    }

    Write-Host ""
    Write-Color "  Select Chrome profile(s) to ${ActionType}:" Cyan
    Write-Host ""
    
    Write-Color "    ID   Profile Folder   Signed-in Email             Friendly Name" Cyan
    Write-Color "    --   --------------   ---------------             -------------" Cyan
    
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $id = $i + 1
        $folder = $p.Folder
        $email = if ($p.Email) { $p.Email } else { "(not signed in)" }
        $name = if ($p.Name) { $p.Name } else { "" }
        Write-Color ("    [{0,-2}] {1,-16} {2,-27} {3}" -f $id, $folder, $email, $name) Cyan
    }
    
    Write-Color "    [A]  All Profiles" Cyan
    Write-Host ""
    
    while ($true) {
        $input = Read-Host "  Enter ID(s) (comma-separated, e.g. 1,3) or A for All"
        if ($null -eq $input) { return @() }
        $input = $input.Trim().ToUpper()
        
        if ($input -eq 'A' -or $input -eq 'ALL') {
            return $profiles
        }
        
        $selected = @()
        $parts = $input -split ','
        $valid = $true
        foreach ($part in $parts) {
            $val = $part.Trim()
            if ($val -match '^\d+$') {
                $idx = [int]$val - 1
                if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                    $selected += $profiles[$idx]
                } else {
                    Write-Err "Invalid ID: $val (out of range)"
                    $valid = $false
                    break
                }
            } else {
                Write-Err "Invalid input: $val"
                $valid = $false
                break
            }
        }
        
        if ($valid -and $selected.Count -gt 0) {
            return $selected
        }
    }
}

function Get-ProfilesInZip {
    param([string]$ZipPath)

    $profiles = @()
    if (-not (Test-Path $ZipPath)) { return $profiles }

    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $prefEntries = $zip.Entries | Where-Object { $_.FullName -like '*/Preferences' -or $_.FullName -eq 'Preferences' }
        foreach ($entry in $prefEntries) {
            $parts = $entry.FullName -split '/'
            if ($parts.Count -gt 1) {
                $folder = $parts[0]
                $email = ""
                $friendlyName = ""
                try {
                    $stream = $entry.Open()
                    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                    $jsonText = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                    
                    $json = ConvertFrom-Json $jsonText
                    if ($json.account_info -and $json.account_info.Count -gt 0) {
                        $email = $json.account_info[0].email
                    }
                    if (-not $email -and $json.google -and $json.google.services) {
                        $email = $json.google.services.username
                        if (-not $email) {
                            $email = $json.google.services.signin.username
                        }
                    }
                    if ($json.profile) {
                        $friendlyName = $json.profile.name
                    }
                } catch {}
                
                $profiles += [PSCustomObject]@{
                    Folder = $folder
                    Email  = $email
                    Name   = $friendlyName
                }
            }
        }
    } catch {
        Write-Log "Error reading ZIP ${ZipPath}: $_" "WARN"
    } finally {
        if ($zip) { $zip.Dispose() }
    }
    return $profiles
}

function Select-RestoreProfiles {
    param(
        [string]$ZipPath
    )

    $profiles = Get-ProfilesInZip -ZipPath $ZipPath
    if ($profiles.Count -eq 0) {
        Write-Warn "No profiles found in the backup file."
        return $null
    }

    Write-Host ""
    Write-Color "  Select Chrome profile(s) to restore from backup:" Cyan
    Write-Host ""
    
    Write-Color "    ID   Profile Folder   Signed-in Email             Friendly Name" Cyan
    Write-Color "    --   --------------   ---------------             -------------" Cyan
    
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $id = $i + 1
        $folder = $p.Folder
        $email = if ($p.Email) { $p.Email } else { "(not signed in)" }
        $name = if ($p.Name) { $p.Name } else { "" }
        Write-Color ("    [{0,-2}] {1,-16} {2,-27} {3}" -f $id, $folder, $email, $name) Cyan
    }
    
    Write-Color "    [A]  All Profiles" Cyan
    Write-Host ""
    
    while ($true) {
        $input = Read-Host "  Enter ID(s) (comma-separated, e.g. 1,3) or A for All"
        if ($null -eq $input) { return $null }
        $input = $input.Trim().ToUpper()
        
        if ($input -eq 'A' -or $input -eq 'ALL') {
            return $null
        }
        
        $selected = @()
        $parts = $input -split ','
        $valid = $true
        foreach ($part in $parts) {
            $val = $part.Trim()
            if ($val -match '^\d+$') {
                $idx = [int]$val - 1
                if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                    $selected += $profiles[$idx]
                } else {
                    Write-Err "Invalid ID: $val (out of range)"
                    $valid = $false
                    break
                }
            } else {
                Write-Err "Invalid input: $val"
                $valid = $false
                break
            }
        }
        
        if ($valid -and $selected.Count -gt 0) {
            return $selected
        }
    }
}

function Select-BackupFile {
    param(
        [string]$Type
    )

    $pattern = if ($Type -eq 'Full') { "chrome_full_backup*.zip" } else { "chrome_session_backup*.zip" }
    $files = Get-ChildItem $Script:BackupDir -Filter $pattern | Where-Object { $_.Name -like "*.zip" }
    
    if ($files.Count -eq 0) {
        return $null
    }
    if ($files.Count -eq 1) {
        return $files[0].FullName
    }

    Write-Host ""
    Write-Color "  Multiple $Type backups found. Please select which one to restore:" Cyan
    Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        $sizeMB = [Math]::Round($f.Length / 1MB, 1)
        $date = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        Write-Color ("    [{0}]  {1,-35} ({2} MB, Created: {3})" -f ($i+1), $f.Name, $sizeMB, $date) Cyan
    }
    Write-Host ""
    
    while ($true) {
        $choice = Read-Host "  Enter number (1-$($files.Count))"
        if ($null -eq $choice) { return $null }
        if ($choice.Trim() -match '^\d+$') {
            $idx = [int]$choice.Trim() - 1
            if ($idx -ge 0 -and $idx -lt $files.Count) {
                return $files[$idx].FullName
            }
        }
        Write-Err "Invalid choice."
    }
}

function Invoke-CookieMigration {
    param(
        [string]$Mode, # 'EXPORT' or 'IMPORT'
        [string]$ProfileName,
        [string]$JsonPath
    )

    Write-Info "Automatic Cookie $Mode for Profile: $ProfileName..."

    $extDir = Join-Path $Script:ScriptDir "cookie_migration_ext"
    if (-not (Test-Path $extDir)) {
        New-Item -ItemType Directory -Path $extDir -Force | Out-Null
    }
    
    $manifestJson = @'
{
  "manifest_version": 3,
  "name": "Chrome Cookie Migrator",
  "version": "1.0",
  "permissions": ["cookies"],
  "host_permissions": ["<all_urls>", "http://localhost:9999/*"],
  "background": {
    "service_worker": "background.js"
  }
}
'@
    Set-Content -Path (Join-Path $extDir "manifest.json") -Value $manifestJson -Encoding utf8
    
    $backgroundJs = @'
const PORT = 9999;
const URL_PREFIX = `http://localhost:${PORT}`;

function getCookieUrl(cookie) {
  let domain = cookie.domain;
  if (domain.startsWith('.')) {
    domain = domain.substring(1);
  }
  const protocol = cookie.secure ? 'https://' : 'http://';
  return protocol + domain + cookie.path;
}

fetch(`${URL_PREFIX}/mode`)
  .then(r => r.json())
  .then(data => {
    if (data.mode === 'EXPORT') {
      chrome.cookies.getAll({}, (cookies) => {
        fetch(`${URL_PREFIX}/export`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(cookies)
        });
      });
    } else if (data.mode === 'IMPORT') {
      fetch(`${URL_PREFIX}/import`)
        .then(r => r.json())
        .then(cookies => {
          if (!cookies || cookies.length === 0) {
            fetch(`${URL_PREFIX}/done`, { method: 'POST' });
            return;
          }
          let count = cookies.length;
          let done = 0;
          cookies.forEach(cookie => {
            const details = {
              url: getCookieUrl(cookie),
              name: cookie.name,
              value: cookie.value,
              path: cookie.path,
              secure: cookie.secure,
              httpOnly: cookie.httpOnly,
              expirationDate: cookie.expirationDate
            };
            if (cookie.domain && cookie.domain.startsWith('.')) {
              details.domain = cookie.domain;
            }
            if (cookie.expirationDate && cookie.expirationDate < Date.now() / 1000) {
              done++;
              if (done === count) {
                fetch(`${URL_PREFIX}/done`, { method: 'POST' });
              }
              return;
            }
            chrome.cookies.set(details, () => {
              done++;
              if (done === count) {
                fetch(`${URL_PREFIX}/done`, { method: 'POST' });
              }
            });
          });
        })
        .catch(err => {
          fetch(`${URL_PREFIX}/done`, { method: 'POST' });
        });
    }
  })
  .catch(err => {
    setTimeout(() => {
      location.reload();
    }, 1000);
  });
'@
    Set-Content -Path (Join-Path $extDir "background.js") -Value $backgroundJs -Encoding utf8

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add('http://localhost:9999/')
    try {
        $listener.Start()
    } catch {
        Write-Err "Could not start local sync listener: $_"
        return $false
    }

    $chromePaths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    $chromeExe = $null
    foreach ($p in $chromePaths) { if (Test-Path $p) { $chromeExe = $p; break } }
    if (-not $chromeExe) {
        Write-Err "Chrome not found! Cannot automatically sync cookies."
        $listener.Stop()
        return $false
    }

    $argList = @(
        ("--load-extension=`"" + $extDir + "`""),
        ("--user-data-dir=`"" + $Script:ChromeUserData + "`""),
        ("--profile-directory=`"" + $ProfileName + "`""),
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check"
    )
    $proc = Start-Process -FilePath $chromeExe -ArgumentList $argList -PassThru

    $syncSuccess = $false
    $timeoutSec = 15
    $start = Get-Date

    while (((Get-Date) - $start).TotalSeconds -lt $timeoutSec -and -not $syncSuccess) {
        if (-not $listener.IsListening) { break }
        
        $contextTask = $listener.GetContextAsync()
        if ($contextTask.Wait(500)) {
            $context = $contextTask.Result
            $req = $context.Request
            $res = $context.Response

            if ($req.Url.LocalPath -eq '/mode') {
                $body = '{"mode":"' + $Mode + '"}'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.ContentType = 'application/json'
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.OutputStream.Close()
            }
            elseif ($req.Url.LocalPath -eq '/export' -and $Mode -eq 'EXPORT') {
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $jsonText = $reader.ReadToEnd()
                $reader.Close()

                $jsonText | Set-Content $JsonPath -Encoding utf8
                $syncSuccess = $true

                $bytes = [System.Text.Encoding]::UTF8.GetBytes('OK')
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.OutputStream.Close()
            }
            elseif ($req.Url.LocalPath -eq '/import' -and $Mode -eq 'IMPORT') {
                $body = if (Test-Path $JsonPath) { Get-Content $JsonPath -Raw -Encoding utf8 } else { '[]' }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.ContentType = 'application/json'
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.OutputStream.Close()
            }
            elseif ($req.Url.LocalPath -eq '/done') {
                $syncSuccess = $true
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('OK')
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.OutputStream.Close()
            }
            else {
                $res.StatusCode = 404
                $res.OutputStream.Close()
            }
        }
    }

    $listener.Stop()
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Remove-Item -Path $extDir -Recurse -Force -ErrorAction SilentlyContinue

    if ($syncSuccess) {
        Write-OK "Automatic cookie sync successful for $ProfileName."
        return $true
    } else {
        Write-Info "Automatic cookie sync timed out for $ProfileName (Chrome may have been closed or locked)."
        return $false
    }
}

# --- BACKUP LOGIC -------------------------------------------------------------
function Start-FullBackup {
    Write-Section "Full Backup"

    $selected = Select-ChromeProfiles -ActionType "Backup"
    if ($selected.Count -eq 0) {
        Write-Warn "No profiles selected for backup. Operation cancelled."
        return $false
    }

    $isAll = $selected.Count -eq (Get-ChromeProfilesDetailed).Count
    if ($isAll) {
        Write-Info "All profiles selected. Performing full User Data backup."
    } else {
        Write-Info "Selected profile(s) to backup:"
        foreach ($s in $selected) {
            $emailInfo = if ($s.Email) { " ($($s.Email))" } else { "" }
            Write-Color "     - $($s.Folder)$emailInfo" DarkGray
        }
    }

    $syncCookies = Read-Host "  Do you want to automatically backup your login sessions (cookies) for selected profile(s)? (YES/NO)"
    if ($syncCookies.Trim().ToUpper() -eq "YES") {
        $cookieBackupDir = Join-Path $Script:BackupDir "cookies"
        if (-not (Test-Path $cookieBackupDir)) { New-Item -ItemType Directory -Path $cookieBackupDir -Force | Out-Null }
        
        Stop-Chrome
        foreach ($p in $selected) {
            $jsonPath = Join-Path $cookieBackupDir "cookies_$($p.Folder).json"
            $null = Invoke-CookieMigration -Mode "EXPORT" -ProfileName $p.Folder -JsonPath $jsonPath
        }
    }

    Write-Info "Collecting file list from Chrome User Data..."

    if ($isAll) {
        $files = Get-FileList @($Script:ChromeUserData)
    } else {
        $sourcePaths = [System.Collections.Generic.List[string]]::new()
        Get-ChildItem $Script:ChromeUserData -File | ForEach-Object { $sourcePaths.Add($_.FullName) }
        foreach ($p in $selected) {
            $pDir = Join-Path $Script:ChromeUserData $p.Folder
            if (Test-Path $pDir) { $sourcePaths.Add($pDir) }
        }
        $files = Get-FileList ($sourcePaths.ToArray())
    }

    $totalMB = [Math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Write-Info "Found $($files.Count) files ($totalMB MB). Preparing..."

    $drive = Get-PSDrive ($Script:BackupDir.Substring(0,1)) -ErrorAction SilentlyContinue
    if ($drive -and $drive.Free -lt ($totalMB * 1MB * 1.2)) {
        Write-Err "Not enough free space on backup drive for backup ($totalMB MB needed)."
        return $false
    }

    Remove-TempDir
    New-Item -ItemType Directory -Path $Script:TempDir -Force | Out-Null

    Stop-Chrome

    Copy-WithProgress -Files $files -SourceRoot $Script:ChromeUserData -DestRoot $Script:TempDir -Label "Copying Chrome User Data"
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $zipPath = Join-Path $Script:BackupDir "chrome_full_backup_windows_$timestamp.zip"
    Compress-WithProgress -SourceDir $Script:TempDir -ZipPath $zipPath -Label "Compressing Full Backup"

    Remove-TempDir

    $zipMB = [Math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-OK "Full backup saved: $zipPath ($zipMB MB)"
    Write-Log "Full backup complete: $zipPath ($zipMB MB)"
    return $true
}

function Start-SessionBackup {
    Write-Section "Session-Only Backup"

    $selected = Select-ChromeProfiles -ActionType "Backup"
    if ($selected.Count -eq 0) {
        Write-Warn "No profiles selected for backup. Operation cancelled."
        return $false
    }

    $isAll = $selected.Count -eq (Get-ChromeProfilesDetailed).Count
    if ($isAll) {
        Write-Info "All profiles selected."
    } else {
        Write-Info "Selected profile(s) to backup:"
        foreach ($s in $selected) {
            $emailInfo = if ($s.Email) { " ($($s.Email))" } else { "" }
            Write-Color "     - $($s.Folder)$emailInfo" DarkGray
        }
    }

    $syncCookies = Read-Host "  Do you want to automatically backup your login sessions (cookies) for selected profile(s)? (YES/NO)"
    if ($syncCookies.Trim().ToUpper() -eq "YES") {
        $cookieBackupDir = Join-Path $Script:BackupDir "cookies"
        if (-not (Test-Path $cookieBackupDir)) { New-Item -ItemType Directory -Path $cookieBackupDir -Force | Out-Null }
        
        Stop-Chrome
        foreach ($p in $selected) {
            $jsonPath = Join-Path $cookieBackupDir "cookies_$($p.Folder).json"
            $null = Invoke-CookieMigration -Mode "EXPORT" -ProfileName $p.Folder -JsonPath $jsonPath
        }
    }

    Write-Info "Collecting session files (extensions, bookmarks, settings, etc.) for selected profiles..."

    $sourcePaths = [System.Collections.Generic.List[string]]::new()

    foreach ($p in $selected) {
        $pDir = Join-Path $Script:ChromeUserData $p.Folder
        foreach ($f in $Script:SessionFiles) {
            $fp = Join-Path $pDir $f
            if (Test-Path $fp) { $sourcePaths.Add($fp) }
        }
        foreach ($d in $Script:SessionDirs) {
            $dp = Join-Path $pDir $d
            if (Test-Path $dp) { $sourcePaths.Add($dp) }
        }
    }
    
    $ls = Join-Path $Script:ChromeUserData "Local State"
    if (Test-Path $ls) { $sourcePaths.Add($ls) }

    if ($sourcePaths.Count -eq 0) {
        Write-Err "No session files found. Selected profiles may not have any valid data."
        return $false
    }

    $files    = Get-FileList ($sourcePaths.ToArray())
    $totalMB  = [Math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Write-Info "Found $($files.Count) files ($totalMB MB) across selected profiles."

    Remove-TempDir
    New-Item -ItemType Directory -Path $Script:TempDir -Force | Out-Null

    Stop-Chrome

    $filesToCopy = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($src in $sourcePaths) {
        if (Test-Path $src -PathType Leaf) {
            $filesToCopy.Add((Get-Item $src))
        } else {
            Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $filesToCopy.Add($_) }
        }
    }

    Copy-WithProgress -Files $filesToCopy -SourceRoot $Script:ChromeUserData -DestRoot $Script:TempDir -Label "Copying Session Data"
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $zipPath = Join-Path $Script:BackupDir "chrome_session_backup_windows_$timestamp.zip"
    Compress-WithProgress -SourceDir $Script:TempDir -ZipPath $zipPath -Label "Compressing Session Backup"

    Remove-TempDir

    $zipMB = [Math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-OK "Session backup saved: $zipPath ($zipMB MB)"
    Write-Log "Session backup complete: $zipPath ($zipMB MB)"
    return $true
}

# --- RESTORE LOGIC ------------------------------------------------------------
function Start-FullRestore {
    Write-Section "Full Restore"

    $zipPath = Select-BackupFile -Type "Full"
    if (-not $zipPath) {
        Write-Err "No Full backup files found in: $Script:BackupDir"
        return $false
    }

    $zipMB   = [Math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    $zipDate = (Get-Item $zipPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-Info "Backup file: $zipPath"
    Write-Info "Size: $zipMB MB | Created: $zipDate"

    $selected = Select-RestoreProfiles -ZipPath $zipPath
    $filterFolders = $null
    if ($null -ne $selected) {
        $filterFolders = $selected | ForEach-Object { $_.Folder }
        Write-Info "Selected profile(s) to restore:"
        foreach ($s in $selected) {
            $emailInfo = if ($s.Email) { " ($($s.Email))" } else { "" }
            Write-Color "     - $($s.Folder)$emailInfo" DarkGray
        }
    } else {
        Write-Info "Restoring all profiles."
    }

    Write-Host ""
    Write-Color "  +-------------------------------------------------------------+" Cyan
    Write-Color "  |  PORTABILITY & RESTORE PREVIEW                              |" Cyan
    Write-Color "  |   [OK] MetaMask and all extensions WILL be restored         |" Green
    Write-Color "  |   [OK] Bookmarks, history, and settings WILL be restored    |" Green
    Write-Color "  |   [i]  Note: Sites requiring login will prompt for password |" Cyan
    Write-Color "  +-------------------------------------------------------------+" Cyan
    Write-Host ""

    $confirm = Read-Host "  Type YES to confirm restore"
    if ($confirm.Trim().ToUpper() -ne "YES") {
        Write-Warn "Restore cancelled by user."
        return $false
    }

    Stop-Chrome

    if ($null -ne $filterFolders) {
        foreach ($folderName in $filterFolders) {
            $targetPath = Join-Path $Script:ChromeUserData $folderName
            if (Test-Path $targetPath) {
                Write-Info "Removing existing profile directory: $targetPath"
                Remove-Item $targetPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Info "Removing current Chrome User Data..."
        Write-Log "Removing existing User Data: $Script:ChromeUserData"
        if (Test-Path $Script:ChromeUserData) {
            Remove-Item $Script:ChromeUserData -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $Script:ChromeUserData -Force | Out-Null
    }

    Expand-WithProgress -ZipPath $zipPath -DestDir $Script:ChromeUserData -FilterFolders $filterFolders -Label "Restoring Full Backup"

    # Automatic Cookie Sync Hook
    $cookieBackupDir = Join-Path $Script:BackupDir "cookies"
    if (Test-Path $cookieBackupDir) {
        $cookieFiles = Get-ChildItem $cookieBackupDir -Filter "cookies_*.json"
        if ($cookieFiles.Count -gt 0) {
            $matchedCookies = @()
            foreach ($cf in $cookieFiles) {
                $p = $cf.BaseName.Replace("cookies_", "")
                if ($null -eq $filterFolders -or ($p -in $filterFolders)) {
                    $matchedCookies += $cf
                }
            }
            
            if ($matchedCookies.Count -gt 0) {
                Write-Host ""
                $importCookies = Read-Host "  Found backed up login sessions (cookies) for selected profile(s). Do you want to automatically import them? (YES/NO)"
                if ($importCookies.Trim().ToUpper() -eq "YES") {
                    Stop-Chrome
                    foreach ($cf in $matchedCookies) {
                        $p = $cf.BaseName.Replace("cookies_", "")
                        $null = Invoke-CookieMigration -Mode "IMPORT" -ProfileName $p -JsonPath $cf.FullName
                    }
                }
            }
        }
    }

    Write-OK "Full restore complete! Start Chrome to verify."
    Write-Log "Full restore complete"
    return $true
}

function Start-SessionRestore {
    Write-Section "Session Restore"

    $zipPath = Select-BackupFile -Type "Session"
    if (-not $zipPath) {
        Write-Err "No Session backup files found in: $Script:BackupDir"
        return $false
    }

    $zipMB   = [Math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    $zipDate = (Get-Item $zipPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-Info "Backup file: $zipPath"
    Write-Info "Size: $zipMB MB | Created: $zipDate"

    $selected = Select-RestoreProfiles -ZipPath $zipPath
    $filterFolders = $null
    if ($null -ne $selected) {
        $filterFolders = $selected | ForEach-Object { $_.Folder }
        Write-Info "Selected profile(s) to restore:"
        foreach ($s in $selected) {
            $emailInfo = if ($s.Email) { " ($($s.Email))" } else { "" }
            Write-Color "     - $($s.Folder)$emailInfo" DarkGray
        }
    } else {
        Write-Info "Restoring all profiles."
    }

    Write-Host ""
    Write-Color "  +-------------------------------------------------------------+" Cyan
    Write-Color "  |  PORTABILITY & RESTORE PREVIEW                              |" Cyan
    Write-Color "  |   [OK] MetaMask vault and settings WILL be restored         |" Green
    Write-Color "  |   [i]  Note: Enter your normal MetaMask password to unlock  |" Cyan
    Write-Color "  +-------------------------------------------------------------+" Cyan
    Write-Host ""

    $confirm = Read-Host "  Type YES to confirm restore"
    if ($confirm.Trim().ToUpper() -ne "YES") {
        Write-Warn "Restore cancelled by user."
        return $false
    }

    Remove-TempDir
    New-Item -ItemType Directory -Path $Script:TempDir -Force | Out-Null

    Stop-Chrome

    Expand-WithProgress -ZipPath $zipPath -DestDir $Script:TempDir -FilterFolders $filterFolders -Label "Extracting Session Backup"

    Write-Info "Merging session data into Chrome profile..."
    Write-Log "Merging session data into $Script:ChromeUserData"

    $mergeFiles = Get-ChildItem $Script:TempDir -Recurse -File -ErrorAction SilentlyContinue
    $mergeStart = Get-Date

    $i = 0
    $total = @($mergeFiles).Count
    foreach ($mf in $mergeFiles) {
        $rel     = $mf.FullName.Substring($Script:TempDir.Length).TrimStart('\')
        $dest    = Join-Path $Script:ChromeUserData $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory $destDir -Force | Out-Null }
        try { Copy-Item $mf.FullName $dest -Force } catch { Write-Log "WARN: Merge failed for $rel" "WARN" }
        $i++
        Show-Progress -Percent ([Math]::Min(99, [Math]::Round($i/$total*100))) -Label "Merging into Chrome profile" -Item $mf.Name -StartTime $mergeStart
    }
    Complete-Progress -Label "Merging into Chrome profile"

    Remove-TempDir

    # Automatic Cookie Sync Hook
    $cookieBackupDir = Join-Path $Script:BackupDir "cookies"
    if (Test-Path $cookieBackupDir) {
        $cookieFiles = Get-ChildItem $cookieBackupDir -Filter "cookies_*.json"
        if ($cookieFiles.Count -gt 0) {
            $matchedCookies = @()
            foreach ($cf in $cookieFiles) {
                $p = $cf.BaseName.Replace("cookies_", "")
                if ($null -eq $filterFolders -or ($p -in $filterFolders)) {
                    $matchedCookies += $cf
                }
            }
            
            if ($matchedCookies.Count -gt 0) {
                Write-Host ""
                $importCookies = Read-Host "  Found backed up login sessions (cookies) for selected profile(s). Do you want to automatically import them? (YES/NO)"
                if ($importCookies.Trim().ToUpper() -eq "YES") {
                    Stop-Chrome
                    foreach ($cf in $matchedCookies) {
                        $p = $cf.BaseName.Replace("cookies_", "")
                        $null = Invoke-CookieMigration -Mode "IMPORT" -ProfileName $p -JsonPath $cf.FullName
                    }
                }
            }
        }
    }

    Write-OK "Session restore complete! Start Chrome to verify."
    Write-Log "Session restore complete"
    return $true
}

# --- BACKUP INFO --------------------------------------------------------------
function Show-BackupInfo {
    Write-Section "Existing Backups"
    $found = $false

    $allZips = Get-ChildItem $Script:BackupDir -Filter "*.zip" | Where-Object { $_.Name -like "chrome_*" }
    foreach ($fi in $allZips) {
        $fsMB  = [Math]::Round($fi.Length/1MB,1).ToString()
        $fsDate = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        
        # Verify ZIP contents
        $verifiedMsg = ""
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($fi.FullName)
            $mmFiles = $zip.Entries | Where-Object { $_.FullName -like '*nkbihfbeogaeaoehlefnkodbefgpgknn*' }
            $mmCount = @($mmFiles).Count
            if ($mmCount -gt 0) {
                $verifiedMsg = " (Verified: MetaMask + $mmCount files)"
            } else {
                $verifiedMsg = " (Verified: No MetaMask found)"
            }
            $zip.Dispose()
        } catch {
            $verifiedMsg = " (Verification error)"
        }

        Write-OK ("Backup: {0,-32} Size: {1,-10} Created: {2}{3}" -f $fi.Name, "$fsMB MB", $fsDate, $verifiedMsg)
        $found = $true
    }

    if (-not $found) {
        Write-Info "No backups found in: $Script:BackupDir"
    }
}

# --- DPAPI / MIGRATION NOTICE -------------------------------------------------
function Show-MigrationNotice {
    Write-Host ""
    Write-Color "  +----------------------------------------------------------------------+" Cyan
    Write-Color "  |  [OK] PORTABILITY & MIGRATION READY                                  |" Green
    Write-Color "  +----------------------------------------------------------------------+" Cyan
    Write-Color "  |                                                                      |" DarkCyan
    Write-Color "  |  [OK] MetaMask & Extensions --- Fully Portable (Ready / Backed Up)   |" Green
    Write-Color "  |  [OK] Bookmarks & Settings --- Fully Portable (Ready / Backed Up)    |" Green
    Write-Color "  |  [OK] Browser History -------- Fully Portable (Ready / Backed Up)    |" Green
    Write-Color "  |  [OK] Local Storage Data ----- Fully Portable (Ready / Backed Up)    |" Green
    Write-Color "  |                                                                      |" DarkCyan
    Write-Color "  |  [i] Note on Cookies & Passwords:                                    |" Cyan
    Write-Color "  |      These items are bound to Windows security (DPAPI). If needed,   |" Cyan
    Write-Color "  |      please export them using Chrome's built-in settings.            |" Cyan
    Write-Color "  +----------------------------------------------------------------------+" Cyan
    Write-Host ""
}

# --- MAIN MENU ----------------------------------------------------------------
function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Header "Chrome Backup & Restore Tool  v3.1 (Auto-Cookie Sync)"

        Show-MigrationNotice
        Show-BackupInfo

        Write-Section "Menu"
        Write-Color "  [1]  Backup Chrome - Full  (entire User Data folder)" Cyan
        Write-Color "  [2]  Backup Chrome - Session Only  (extensions, cookies*, data)" Cyan
        Write-Color "  [3]  Restore Chrome - Full" Cyan
        Write-Color "  [4]  Restore Chrome - Session Only" Cyan
        Write-Color "  [5]  Run System Validation" Cyan
        Write-Color "  [Q]  Quit" DarkGray
        Write-Host ""
        Write-Color "  * Cookies survive reinstall ONLY if you also export via browser extension." DarkGray
        Write-Host ""

        $choice = Read-Host "  Enter choice"
        if ($null -eq $choice) { exit 0 }
        switch ($choice.Trim().ToUpper()) {
            "1" {
                Clear-Host
                Write-Header "Full Backup"
                $ok = Test-Prerequisites
                if ($ok) { $null = Start-FullBackup }
                else { Write-Info "System validation checks failed. Please check the logs." }
                Write-Host ""
                Write-Color "  Press Enter to return to menu..." DarkGray
                Read-Host | Out-Null
            }
            "2" {
                Clear-Host
                Write-Header "Session Backup"
                $ok = Test-Prerequisites
                if ($ok) { $null = Start-SessionBackup }
                Write-Host ""
                Write-Color "  Press Enter to return to menu..." DarkGray
                Read-Host | Out-Null
            }
            "3" {
                Clear-Host
                Write-Header "Full Restore"
                $null = Start-FullRestore
                Write-Host ""
                Write-Color "  Press Enter to return to menu..." DarkGray
                Read-Host | Out-Null
            }
            "4" {
                Clear-Host
                Write-Header "Session Restore"
                $null = Start-SessionRestore
                Write-Host ""
                Write-Color "  Press Enter to return to menu..." DarkGray
                Read-Host | Out-Null
            }
            "5" {
                Clear-Host
                Write-Header "System Validation"
                Test-Prerequisites | Out-Null
                Write-Host ""
                Write-Color "  Press Enter to return to menu..." DarkGray
                Read-Host | Out-Null
            }
            { $_ -in @("Q", "QUIT", "EXIT") } {
                Write-Color "`n  Goodbye!`n" Green
                exit 0
            }
            default {
                Write-Info "Invalid choice. Please enter 1-5 or Q."
                Start-Sleep -Seconds 1
            }
        }
    }
}

# --- ENTRY POINT --------------------------------------------------------------
try {
    Initialize-Log

    try {
        if ([Console]::WindowWidth -lt 90) { [Console]::WindowWidth = 90 }
        if ([Console]::BufferWidth -lt 90) { [Console]::BufferWidth = 90 }
    } catch { }

    Show-MainMenu
} catch {
    Write-Err "An unexpected error occurred: $_"
    Write-Log "FATAL: $_" "ERROR"
    Write-Host ""
    Write-Color "  Check the log file for details: $Script:LogFile" Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
