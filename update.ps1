<#
.SYNOPSIS
    HALEEM-ULTRA — Bulletproof Updater v3.0
.DESCRIPTION
    Updates HALEEM-ULTRA plugin to the latest version.
    Works on ALL machines including Arabic/Unicode usernames.
    Multiple fallback methods for download, extraction, and verification.
    
    Run as Administrator:
    Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/haleemrz/HALEEM-ULTRA-TestReleases/master/update.ps1 | iex
#>

# ═══════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ─── Helpers ──────────────────────────────────────────────
function WOK  { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function WWRN { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function WERR { param([string]$m) Write-Host "  [XX] $m" -ForegroundColor Red }
function WINF { param([string]$m) Write-Host "  [..] $m" -ForegroundColor Cyan }
function WHDR { param([int]$n,[int]$t,[string]$m) Write-Host "`n[$n/$t] $m" -ForegroundColor Cyan }

# ─── Safe download (4 methods) ───────────────────────────
function Safe-Download {
    param([string]$Url, [string]$OutFile, [int]$MinSize = 1000)
    
    # Method 1: WebClient
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "HALEEM-ULTRA-Updater/3.0")
        $wc.DownloadFile($Url, $OutFile)
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "WebClient failed, trying next..." }
    
    # Method 2: Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -UserAgent "HALEEM-ULTRA-Updater/3.0"
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "Invoke-WebRequest failed, trying next..." }
    
    # Method 3: curl.exe
    try {
        $curlExe = "C:\Windows\System32\curl.exe"
        if (Test-Path $curlExe) {
            $curlOut = cmd /c "`"$curlExe`" -L -o `"$OutFile`" -A `"HALEEM-ULTRA`" --silent --show-error `"$Url`""
            if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
        }
    } catch { WINF "curl.exe failed, trying next..." }
    
    # Method 4: BitsTransfer
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $Url -Destination $OutFile -Description "HALEEM-ULTRA Update"
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "BitsTransfer failed" }
    
    return $false
}

# ─── Safe extract (4 methods) ────────────────────────────
function Safe-Extract {
    param([string]$ZipFile, [string]$DestDir)
    
    # Method 1: Expand-Archive
    try {
        Expand-Archive -Path $ZipFile -DestinationPath $DestDir -Force
        return $true
    } catch { WINF "Expand-Archive failed, trying next..." }
    
    # Method 2: .NET ZipFile (entry-by-entry, most reliable)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
        foreach ($entry in $archive.Entries) {
            $destPath = Join-Path $DestDir $entry.FullName
            $destParent = Split-Path $destPath -Parent
            if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
            if ($entry.Name) {
                $stream = $entry.Open()
                $fileStream = [System.IO.File]::Create($destPath)
                $stream.CopyTo($fileStream)
                $fileStream.Close()
                $stream.Close()
            }
        }
        $archive.Dispose()
        return $true
    } catch { WINF ".NET ZipFile failed, trying next..." }
    
    # Method 3: COM Shell
    try {
        $shell = New-Object -ComObject Shell.Application
        $zipFolder = $shell.NameSpace($ZipFile)
        $destFolder = $shell.NameSpace($DestDir)
        $destFolder.CopyHere($zipFolder.Items(), 0x14)
        Start-Sleep -Seconds 3
        return $true
    } catch { WINF "COM Shell failed, trying next..." }
    
    # Method 4: tar.exe
    try {
        $tarExe = "C:\Windows\System32\tar.exe"
        if (Test-Path $tarExe) {
            Push-Location $DestDir
            $tarOut = cmd /c "`"$tarExe`" -xf `"$ZipFile`""
            Pop-Location
            return $true
        }
    } catch { try { Pop-Location } catch {}; WINF "tar.exe failed" }
    
    return $false
}

# ─── Safe command runner ─────────────────────────────────
function Safe-Run {
    param([string]$Exe, [string[]]$Args)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Args -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; Output = $stdout; Error = $stderr }
}

# ═══════════════════════════════════════════════════════════
#  Configuration
# ═══════════════════════════════════════════════════════════
$REPO_OWNER = "haleemrz"
$REPO_NAME  = "HALEEM-ULTRA-Releases"
$TOTAL_STEPS = 9

$_hasUnicode = $env:USERPROFILE -match '[^\x00-\x7F]'
$TEMP_DIR = if ($_hasUnicode) { "C:\haleem-temp" } else { "$env:TEMP\haleem-update" }

# Locate plugin directory (multiple candidates)
$EXT_DIR = Join-Path $env:APPDATA "Adobe\CEP\extensions"
$PLUGIN_DIR = Join-Path $EXT_DIR "com.haleem.ultra.client"
$VENV_DIR = Join-Path $EXT_DIR ".venv"
$PIP_EXE  = Join-Path $VENV_DIR "Scripts\pip.exe"
$VENV_PY  = Join-Path $VENV_DIR "Scripts\python.exe"

# ═══════════════════════════════════════════════════════════
#  STEP 0: Pre-flight
# ═══════════════════════════════════════════════════════════

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    WERR "Run as Administrator! Right-click PowerShell -> Run as Administrator"
    return
}

Write-Host ""
Write-Host "  +=============================================+" -ForegroundColor Cyan
Write-Host "  |  HALEEM-ULTRA  Updater v3.0 (Bulletproof)  |" -ForegroundColor Cyan
Write-Host "  +=============================================+" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════
#  STEP 1: Find existing installation
# ═══════════════════════════════════════════════════════════
WHDR 1 $TOTAL_STEPS "Checking existing installation"

if (-not (Test-Path $PLUGIN_DIR)) {
    # Search alternate locations
    $altPaths = @(
        "$env:APPDATA\Adobe\CEP\extensions\com.haleem.ultra.client",
        "${env:ProgramFiles}\Adobe\Adobe Premiere Pro 2024\CEPServiceManager4\extensions\com.haleem.ultra.client",
        "${env:ProgramFiles}\Adobe\Adobe Premiere Pro 2025\CEPServiceManager4\extensions\com.haleem.ultra.client"
    )
    $found = $false
    foreach ($alt in $altPaths) {
        if (Test-Path $alt) {
            $PLUGIN_DIR = $alt
            $EXT_DIR = Split-Path $PLUGIN_DIR
            $found = $true
            break
        }
    }
    if (-not $found) {
        WERR "HALEEM-ULTRA not found! Run install.ps1 first."
        WERR "البلجن غير مثبتة! شغّل سكربت التثبيت أولاً."
        return
    }
}

# Read current version
$currentVer = "unknown"
$verFile = Join-Path $PLUGIN_DIR "version.json"
if (Test-Path $verFile) {
    try { $currentVer = (Get-Content $verFile -Raw | ConvertFrom-Json).version } catch {}
}
WOK "Plugin found at: $PLUGIN_DIR"
WINF "Current version: $currentVer"

# ═══════════════════════════════════════════════════════════
#  STEP 2: Detect latest update from GitHub
# ═══════════════════════════════════════════════════════════
WHDR 2 $TOTAL_STEPS "Checking for updates"

$updateVersion = ""
$updateUrl = ""

try {
    $apiUrl = "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases?per_page=10"
    $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    
    # First try: find update zip (patch)
    foreach ($rel in $releases) {
        $updateZip = $rel.assets | Where-Object { $_.name -match '^update-v.*\.zip$' } | Select-Object -First 1
        if ($updateZip) {
            $relVer = $rel.tag_name -replace '^v', ''
            if ($relVer -ne $currentVer) {
                $updateVersion = $relVer
                $updateUrl = $updateZip.browser_download_url
                break
            }
        }
    }
    
    # If no update found, try full release
    if (-not $updateUrl) {
        foreach ($rel in $releases) {
            $fullZip = $rel.assets | Where-Object { $_.name -match '^haleem-ultra-v.*\.zip$' } | Select-Object -First 1
            if ($fullZip) {
                $relVer = $rel.tag_name -replace '^v', ''
                if ($relVer -ne $currentVer) {
                    $updateVersion = $relVer
                    $updateUrl = $fullZip.browser_download_url
                }
                break
            }
        }
    }
} catch {
    WWRN "Could not check GitHub API: $_"
}

if (-not $updateUrl) {
    WOK "Already on latest version ($currentVer). No update needed."
    WOK "أنت على آخر إصدار. لا يوجد تحديث."
    
    # Still run verification
    WINF "Running verification anyway..."
} else {
    WINF "Update available: v$currentVer -> v$updateVersion"
    WINF "URL: $updateUrl"
}

# ═══════════════════════════════════════════════════════════
#  STEP 3: Close Premiere Pro
# ═══════════════════════════════════════════════════════════
WHDR 3 $TOTAL_STEPS "Checking Premiere Pro"

$premiere = Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue
if ($premiere) {
    WWRN "Premiere Pro is running! / بريمير مفتوح!"
    WWRN "Close Premiere Pro and run again, or press Enter to force close."
    $input = Read-Host "  Force close Premiere? (y/n)"
    if ($input -eq "y") {
        $premiere | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        $still = Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue
        if ($still) { $still | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
        WOK "Premiere Pro closed"
    } else {
        WERR "Close Premiere Pro first! / أغلق بريمير أولاً!"
        return
    }
} else {
    WOK "Premiere Pro is not running"
}

# ═══════════════════════════════════════════════════════════
#  STEP 4: Backup critical files
# ═══════════════════════════════════════════════════════════
WHDR 4 $TOTAL_STEPS "Backing up current version"

if (Test-Path $TEMP_DIR) { Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

$backupDir = "$TEMP_DIR\backup_v$currentVer"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$backupFiles = @("index.html", "version.json", "activation-gate.js", "update-checker.js", "impact-captions.js", "template-engine.js", "templates.json")
$backedUp = 0
foreach ($f in $backupFiles) {
    $src = Join-Path $PLUGIN_DIR $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $backupDir $f) -Force -ErrorAction SilentlyContinue
        $backedUp++
    }
}
WOK "Backed up $backedUp files to $backupDir"

# ═══════════════════════════════════════════════════════════
#  STEP 5: Download update
# ═══════════════════════════════════════════════════════════
WHDR 5 $TOTAL_STEPS "Downloading update"

$updateApplied = $false

if ($updateUrl) {
    $zipFile = "$TEMP_DIR\update.zip"
    
    WINF "Downloading v$updateVersion..."
    $dlOK = Safe-Download $updateUrl $zipFile 50000
    
    if ($dlOK) {
        $zipSize = [math]::Round((Get-Item $zipFile).Length / 1KB)
        WOK "Downloaded ($zipSize KB)"
    } else {
        WERR "Download failed after all 4 methods!"
        WERR "Try manually: $updateUrl"
        WWRN "Continuing with verification only..."
    }
    
    # ═══════════════════════════════════════════════════════════
    #  STEP 6: Extract update (Unicode-safe)
    # ═══════════════════════════════════════════════════════════
    WHDR 6 $TOTAL_STEPS "Installing update"
    
    if ($dlOK) {
        if ($_hasUnicode) {
            # Extract to safe temp first, then robocopy
            $extractTemp = "$TEMP_DIR\update-extract"
            New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null
            
            WINF "Extracting to safe temp path..."
            $exOK = Safe-Extract $zipFile $extractTemp
            
            if ($exOK) {
                # Handle nested folder
                $items = Get-ChildItem $extractTemp
                $sourceDir = $extractTemp
                if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $sourceDir = $items[0].FullName }
                
                WINF "Copying to plugin directory..."
                $robocopyOut = cmd /c "robocopy `"$sourceDir`" `"$PLUGIN_DIR`" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS /NP"
                $updateApplied = $true
                WOK "Update extracted and copied"
            } else {
                # Fallback: try direct
                WWRN "Temp extract failed, trying direct..."
                $exOK2 = Safe-Extract $zipFile $PLUGIN_DIR
                if ($exOK2) { $updateApplied = $true; WOK "Update extracted (direct)" }
                else { WERR "All extraction methods failed!" }
            }
        } else {
            # Direct extract
            WINF "Extracting..."
            $exOK = Safe-Extract $zipFile $PLUGIN_DIR
            if ($exOK) { $updateApplied = $true; WOK "Update extracted" }
            else { WERR "All extraction methods failed!" }
        }
    }
} else {
    WINF "No update to download. Skipping to verification."
}

# ═══════════════════════════════════════════════════════════
#  STEP 6b: Write version.json (no BOM)
# ═══════════════════════════════════════════════════════════
if ($updateApplied -and $updateVersion) {
    WINF "Writing version.json..."
    $versionJson = "{`"version`":`"$updateVersion`"}"
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $PLUGIN_DIR "version.json"), $versionJson, $utf8NoBom)
        WOK "version.json updated to v$updateVersion (no BOM)"
    } catch {
        try {
            Set-Content -Path (Join-Path $PLUGIN_DIR "version.json") -Value $versionJson -Force
            WOK "version.json updated (fallback)"
        } catch {
            WWRN "Could not write version.json"
        }
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 7: Repair Python packages (if needed)
# ═══════════════════════════════════════════════════════════
WHDR 7 $TOTAL_STEPS "Checking Python environment"

$pipOK = $false
if (Test-Path $VENV_PY) {
    # Quick health check: try importing critical packages
    $healthTest = Safe-Run $VENV_PY @("-c", "import torch, whisper, numpy, librosa; print('OK')")
    if ($healthTest.ExitCode -eq 0 -and $healthTest.Output.Trim() -eq "OK") {
        WOK "All Python packages healthy"
        $pipOK = $true
    } else {
        WWRN "Some packages need repair..."
        
        # Re-install from requirements.txt
        $reqFile = Join-Path $PLUGIN_DIR "requirements.txt"
        if (Test-Path $reqFile) {
            WINF "Reinstalling from requirements.txt..."
            $reqResult = Safe-Run $PIP_EXE @("install", "--isolated", "-r", $reqFile)
            
            # Re-test
            $healthTest2 = Safe-Run $VENV_PY @("-c", "import torch, whisper, numpy, librosa; print('OK')")
            if ($healthTest2.ExitCode -eq 0) {
                WOK "Packages repaired"
                $pipOK = $true
            } else {
                WWRN "Some packages still failing. Run install.ps1 for full repair."
            }
        }
    }
} else {
    WERR ".venv not found! Run install.ps1 first."
    WERR "البيئة الافتراضية غير موجودة! شغّل سكربت التثبيت."
}

# ═══════════════════════════════════════════════════════════
#  STEP 8: Repair Silero VAD (if patched file was overwritten)
# ═══════════════════════════════════════════════════════════
WHDR 8 $TOTAL_STEPS "Silero VAD model check"

$sileroModel = Join-Path $PLUGIN_DIR "ai_models\silero_vad.onnx"
if (Test-Path $sileroModel) {
    WOK "Silero model present"
    
    # Re-patch silero_detector.py if update overwrote it
    $detPy = Join-Path $PLUGIN_DIR "speech_detection\silero_detector.py"
    if (Test-Path $detPy) {
        $detContent = [System.IO.File]::ReadAllText($detPy, [System.Text.Encoding]::UTF8)
        if ($detContent -match "_SILERO_LOCAL" -or $detContent -match "_ONNX_MODEL_LOCAL" -or $detContent -match "_BUNDLED_MODEL") {
            WOK "silero_detector.py patch intact"
        } elseif ($detContent -match '_ONNX_MODEL\s*=\s*os\.path\.join\(_SILERO_CACHE') {
            WINF "Re-patching silero_detector.py..."
            $oldPattern = '_ONNX_MODEL = os.path.join(_SILERO_CACHE, "silero_vad.onnx")'
            $newCode = @'
_SILERO_LOCAL = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "ai_models", "silero_vad.onnx"
)
_ONNX_MODEL = _SILERO_LOCAL if os.path.exists(_SILERO_LOCAL) else os.path.join(_SILERO_CACHE, "silero_vad.onnx")
'@
            $detContent = $detContent.Replace($oldPattern, $newCode)
            [System.IO.File]::WriteAllText($detPy, $detContent, [System.Text.Encoding]::UTF8)
            WOK "silero_detector.py re-patched"
        }
    }
    
    # Ensure model in torch cache
    $cacheDir = Join-Path $env:USERPROFILE ".cache\torch\hub\snakers4_silero-vad_master\src\silero_vad\data"
    $cacheFile = Join-Path $cacheDir "silero_vad.onnx"
    if (-not (Test-Path $cacheFile)) {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        Copy-Item $sileroModel $cacheFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $cacheFile) { WOK "Model copied to torch cache" }
    }
} else {
    WWRN "Silero model missing from ai_models/"
}

# ═══════════════════════════════════════════════════════════
#  STEP 9: COMPREHENSIVE VERIFICATION
# ═══════════════════════════════════════════════════════════
WHDR 9 $TOTAL_STEPS "Comprehensive Verification"

Write-Host ""
$allOK = $true
$failCount = 0

# --- Plugin Files ---
Write-Host "  --- Plugin Files ---" -ForegroundColor White
$fileChecks = @(
    @{ N = "index.html";                  P = (Join-Path $PLUGIN_DIR "index.html") },
    @{ N = "CSXS/manifest.xml";           P = (Join-Path $PLUGIN_DIR "CSXS\manifest.xml") },
    @{ N = "host/premiere.jsx";           P = (Join-Path $PLUGIN_DIR "host\premiere.jsx") },
    @{ N = "backend_server.pyc";          P = (Join-Path $PLUGIN_DIR "scripts\backend_server.pyc") },
    @{ N = "process_video.pyc";           P = (Join-Path $PLUGIN_DIR "scripts\process_video.pyc") },
    @{ N = "version.json";                P = (Join-Path $PLUGIN_DIR "version.json") },
    @{ N = "activation-gate.js";          P = (Join-Path $PLUGIN_DIR "activation-gate.js") },
    @{ N = "requirements.txt";            P = (Join-Path $PLUGIN_DIR "requirements.txt") },
    @{ N = "ai_models/silero_vad.onnx";   P = (Join-Path $PLUGIN_DIR "ai_models\silero_vad.onnx") },
    @{ N = "broll-server/server.js";      P = (Join-Path $PLUGIN_DIR "broll-server\server.js") },
    @{ N = "broll-server/node_modules";   P = (Join-Path $PLUGIN_DIR "broll-server\node_modules") }
)

foreach ($c in $fileChecks) {
    if (Test-Path $c.P) { WOK $c.N }
    else { WERR "$($c.N) — MISSING"; $allOK = $false; $failCount++ }
}

# --- Directories ---
Write-Host ""
Write-Host "  --- Directories ---" -ForegroundColor White
$dirChecks = @("audio_engine", "core", "scripts", "silence_detection", "speech_detection", "video_engine", "waveform_analysis", "vendor")
foreach ($d in $dirChecks) {
    $dp = Join-Path $PLUGIN_DIR $d
    if (Test-Path $dp) { WOK $d }
    else { WERR "$d — MISSING"; $allOK = $false; $failCount++ }
}

# --- Version ---
Write-Host ""
Write-Host "  --- Version ---" -ForegroundColor White
$finalVer = "unknown"
try { $finalVer = (Get-Content (Join-Path $PLUGIN_DIR "version.json") -Raw | ConvertFrom-Json).version } catch {}
if ($updateApplied -and $updateVersion) {
    if ($finalVer -eq $updateVersion) { WOK "Version: v$finalVer (updated from v$currentVer)" }
    else { WWRN "Version mismatch: expected v$updateVersion, got v$finalVer" }
} else {
    WOK "Version: v$finalVer"
}

# --- Runtime ---
Write-Host ""
Write-Host "  --- Runtime ---" -ForegroundColor White

if (Test-Path $VENV_PY) { WOK ".venv Python" } else { WERR ".venv missing!"; $allOK = $false; $failCount++ }

# FFmpeg
$ffOK = $false
try { $null = Get-Command ffmpeg -ErrorAction Stop; $ffOK = $true } catch {}
if (-not $ffOK -and (Test-Path "C:\ffmpeg\ffmpeg.exe")) { $ffOK = $true }
if ($ffOK) { WOK "FFmpeg" } else { WWRN "FFmpeg not in PATH" }

# CEP
$cepOK = $true
foreach ($v in @("9","10","11","12")) {
    $val = (Get-ItemProperty -Path "HKCU:\Software\Adobe\CSXS.$v" -Name "PlayerDebugMode" -ErrorAction SilentlyContinue).PlayerDebugMode
    if ($val -ne "1") { $cepOK = $false }
}
if ($cepOK) { WOK "CEP Debug Mode" } else { WERR "CEP Debug Mode not enabled"; $allOK = $false; $failCount++ }

# --- Package Imports ---
Write-Host ""
Write-Host "  --- Package Imports ---" -ForegroundColor White

if (Test-Path $VENV_PY) {
    $imports = @(
        @{ N = "torch";       C = "import torch; print(torch.__version__)" },
        @{ N = "numpy";       C = "import numpy; print(numpy.__version__)" },
        @{ N = "whisper";     C = "import whisper; print(whisper.__version__)" },
        @{ N = "librosa";     C = "import librosa; print(librosa.__version__)" },
        @{ N = "onnxruntime"; C = "import onnxruntime; print(onnxruntime.__version__)" }
    )
    foreach ($t in $imports) {
        $result = Safe-Run $VENV_PY @("-c", $t.C)
        if ($result.ExitCode -eq 0) { WOK "$($t.N) $($result.Output.Trim())" }
        else { WERR "$($t.N) — IMPORT FAILED"; $failCount++ }
    }
}

# ═══════════════════════════════════════════════════════════
#  Cleanup
# ═══════════════════════════════════════════════════════════
try { Remove-Item "$TEMP_DIR\update.zip" -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item "$TEMP_DIR\update-extract" -Recurse -Force -ErrorAction SilentlyContinue } catch {}

# ═══════════════════════════════════════════════════════════
#  Final Result
# ═══════════════════════════════════════════════════════════
Write-Host ""
if ($allOK -and $failCount -eq 0) {
    if ($updateApplied) {
        Write-Host "  +=============================================+" -ForegroundColor Green
        Write-Host "  |  [OK] Update successful!                    |" -ForegroundColor Green
        Write-Host "  |  [OK] v$currentVer -> v$updateVersion                          |" -ForegroundColor Green
        Write-Host "  |  [OK] All checks passed                     |" -ForegroundColor Green
        Write-Host "  |                                             |" -ForegroundColor Green
        Write-Host "  |  Open Premiere Pro > Extensions > HALEEM    |" -ForegroundColor Green
        Write-Host "  +=============================================+" -ForegroundColor Green
    } else {
        Write-Host "  +=============================================+" -ForegroundColor Green
        Write-Host "  |  [OK] All checks passed!                    |" -ForegroundColor Green
        Write-Host "  |  [OK] Version: v$finalVer                          |" -ForegroundColor Green
        Write-Host "  |  [OK] Everything is working correctly       |" -ForegroundColor Green
        Write-Host "  +=============================================+" -ForegroundColor Green
    }
} elseif ($failCount -le 3) {
    Write-Host "  +=============================================+" -ForegroundColor Yellow
    Write-Host "  |  [!!] Completed with $failCount warning(s)           |" -ForegroundColor Yellow
    Write-Host "  |  Review warnings above.                     |" -ForegroundColor Yellow
    Write-Host "  |  Backup at: $backupDir" -ForegroundColor Yellow
    Write-Host "  +=============================================+" -ForegroundColor Yellow
} else {
    Write-Host "  +=============================================+" -ForegroundColor Red
    Write-Host "  |  [XX] $failCount issues found                        |" -ForegroundColor Red
    Write-Host "  |  Run install.ps1 for full repair.           |" -ForegroundColor Red
    Write-Host "  |  Backup at: $backupDir" -ForegroundColor Red
    Write-Host "  +=============================================+" -ForegroundColor Red
}
Write-Host ""
