<#
.SYNOPSIS
    HALEEM-ULTRA - Bulletproof Updater v3.1
.DESCRIPTION
    Updates HALEEM-ULTRA plugin to the latest version.
    Works on ALL machines including Arabic/Unicode usernames.
    
    Run as Administrator:
    Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/haleemrz/HALEEM-ULTRA-TestReleases/master/update.ps1 | iex
#>

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ─── Helpers ──────────────────────────────────────────────
function WOK  { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function WWRN { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function WERR { param([string]$m) Write-Host "  [XX] $m" -ForegroundColor Red }
function WINF { param([string]$m) Write-Host "  [..] $m" -ForegroundColor Cyan }
function WSKP { param([string]$m) Write-Host "  [--] $m" -ForegroundColor DarkGray }
function WHDR { param([int]$n,[int]$t,[string]$m) Write-Host "`n[$n/$t] $m" -ForegroundColor Cyan }

# ─── Quick test ───────────────────────────────────────────
function Quick-Test {
    param([string]$Exe, [string[]]$CmdArgs)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $CmdArgs -join " "
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $ok = $proc.WaitForExit(15000)
        if (-not $ok) { $proc.Kill(); return @{ OK = $false; Out = "timeout" } }
        return @{ OK = ($proc.ExitCode -eq 0); Out = $stdout.Trim(); Err = $stderr.Trim() }
    } catch {
        return @{ OK = $false; Out = ""; Err = $_.Exception.Message }
    }
}

# ─── Safe download (4 methods) ───────────────────────────
function Safe-Download {
    param([string]$Url, [string]$OutFile, [int]$MinSize = 1000)
    
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
    
    try {
        WINF "Downloading via WebClient..."
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "HALEEM-ULTRA-Updater/3.1")
        $wc.DownloadFile($Url, $OutFile)
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "WebClient failed, trying next..." }
    
    try {
        $curlExe = "C:\Windows\System32\curl.exe"
        if (Test-Path $curlExe) {
            WINF "Downloading via curl..."
            cmd /c "`"$curlExe`" -L -o `"$OutFile`" -# `"$Url`""
            if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
        }
    } catch { WINF "curl failed, trying next..." }
    
    try {
        WINF "Downloading via Invoke-WebRequest..."
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "IWR failed, trying next..." }
    
    try {
        WINF "Downloading via BitsTransfer..."
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $Url -Destination $OutFile -Description "HALEEM-ULTRA"
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "BitsTransfer failed" }
    
    return $false
}

# ─── Safe extract (4 methods) ────────────────────────────
function Safe-Extract {
    param([string]$ZipFile, [string]$DestDir)
    
    try { Expand-Archive -Path $ZipFile -DestinationPath $DestDir -Force; return $true }
    catch { WINF "Expand-Archive failed, trying .NET..." }
    
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
        $archive.Dispose(); return $true
    } catch { WINF ".NET ZipFile failed, trying COM..." }
    
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.NameSpace($DestDir).CopyHere($shell.NameSpace($ZipFile).Items(), 0x14)
        Start-Sleep -Seconds 3; return $true
    } catch { WINF "COM Shell failed, trying tar..." }
    
    try {
        if (Test-Path "C:\Windows\System32\tar.exe") {
            Push-Location $DestDir
            cmd /c "tar.exe -xf `"$ZipFile`""
            Pop-Location; return $true
        }
    } catch { try { Pop-Location } catch {} }
    
    return $false
}

# ═══════════════════════════════════════════════════════════
#  Configuration
# ═══════════════════════════════════════════════════════════
$REPO_OWNER = "haleemrz"
$REPO_NAME  = "HALEEM-ULTRA-Releases"
$TOTAL = 9

$_hasUnicode = $env:USERPROFILE -match '[^\x00-\x7F]'
$TEMP_DIR = if ($_hasUnicode) { "C:\haleem-temp" } else { "$env:TEMP\haleem-update" }

$EXT_DIR    = Join-Path $env:APPDATA "Adobe\CEP\extensions"
$PLUGIN_DIR = Join-Path $EXT_DIR "com.haleem.ultra.client"
$VENV_DIR   = Join-Path $EXT_DIR ".venv"
$PIP_EXE    = Join-Path $VENV_DIR "Scripts\pip.exe"
$VENV_PY    = Join-Path $VENV_DIR "Scripts\python.exe"

# ═══════════════════════════════════════════════════════════
#  STEP 0: Pre-flight
# ═══════════════════════════════════════════════════════════
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { WERR "Run as Administrator!"; return }

Write-Host ""
Write-Host "  +=============================================+" -ForegroundColor Cyan
Write-Host "  |  HALEEM-ULTRA  Updater v3.1 (Bulletproof)  |" -ForegroundColor Cyan
Write-Host "  +=============================================+" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════
#  STEP 1: Find existing installation
# ═══════════════════════════════════════════════════════════
WHDR 1 $TOTAL "Checking existing installation"

if (-not (Test-Path $PLUGIN_DIR)) {
    $altPaths = @(
        "$env:APPDATA\Adobe\CEP\extensions\com.haleem.ultra.client",
        "${env:ProgramFiles}\Adobe\Adobe Premiere Pro 2024\CEPServiceManager4\extensions\com.haleem.ultra.client",
        "${env:ProgramFiles}\Adobe\Adobe Premiere Pro 2025\CEPServiceManager4\extensions\com.haleem.ultra.client"
    )
    $found = $false
    foreach ($alt in $altPaths) {
        if (Test-Path $alt) { $PLUGIN_DIR = $alt; $EXT_DIR = Split-Path $PLUGIN_DIR; $found = $true; break }
    }
    if (-not $found) {
        WERR "HALEEM-ULTRA not found! Run install.ps1 first."
        return
    }
}

$currentVer = "unknown"
$verFile = Join-Path $PLUGIN_DIR "version.json"
if (Test-Path $verFile) {
    try { $currentVer = (Get-Content $verFile -Raw | ConvertFrom-Json).version } catch {}
}
WOK "Plugin found: $PLUGIN_DIR"
WINF "Current version: $currentVer"

# ═══════════════════════════════════════════════════════════
#  STEP 2: Check for updates
# ═══════════════════════════════════════════════════════════
WHDR 2 $TOTAL "Checking for updates"

$updateVersion = ""
$updateUrl = ""

try {
    $apiUrl = "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases?per_page=10"
    $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    
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
    
    if (-not $updateUrl) {
        foreach ($rel in $releases) {
            $fullZip = $rel.assets | Where-Object { $_.name -match '^haleem-ultra-v.*\.zip$' } | Select-Object -First 1
            if ($fullZip) {
                $relVer = $rel.tag_name -replace '^v', ''
                if ($relVer -ne $currentVer) { $updateVersion = $relVer; $updateUrl = $fullZip.browser_download_url }
                break
            }
        }
    }
} catch {
    $errMsg = "$_"
    WWRN "Could not check GitHub API: $errMsg"
}

if (-not $updateUrl) {
    WOK "Already on latest version: v$currentVer"
    WINF "Running verification anyway..."
} else {
    WINF "Update available: v$currentVer -> v$updateVersion"
}

# ═══════════════════════════════════════════════════════════
#  STEP 3: Close Premiere Pro
# ═══════════════════════════════════════════════════════════
WHDR 3 $TOTAL "Checking Premiere Pro"

$premiere = Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue
if ($premiere) {
    WWRN "Premiere Pro is running!"
    $resp = Read-Host "  Force close? (y/n)"
    if ($resp -eq "y") {
        $premiere | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        $still = Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue
        if ($still) { $still | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
        WOK "Premiere Pro closed"
    } else { WERR "Close Premiere Pro first!"; return }
} else {
    WOK "Premiere Pro is not running"
}

# ═══════════════════════════════════════════════════════════
#  STEP 4: Backup
# ═══════════════════════════════════════════════════════════
WHDR 4 $TOTAL "Backing up"

if (Test-Path $TEMP_DIR) { Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

$backupDir = "$TEMP_DIR\backup_v$currentVer"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$backed = 0
foreach ($f in @("index.html","version.json","activation-gate.js","update-checker.js","impact-captions.js","template-engine.js","templates.json")) {
    $src = Join-Path $PLUGIN_DIR $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $backupDir $f) -Force -ErrorAction SilentlyContinue; $backed++ }
}
WOK "Backed up $backed files"

# ═══════════════════════════════════════════════════════════
#  STEP 5 & 6: Download & Install update
# ═══════════════════════════════════════════════════════════
WHDR 5 $TOTAL "Downloading update"

$updateApplied = $false

if ($updateUrl) {
    $zipFile = "$TEMP_DIR\update.zip"
    
    WINF "Downloading v$updateVersion..."
    $dlOK = Safe-Download $updateUrl $zipFile 50000
    
    if ($dlOK) {
        $zipSizeKB = [math]::Round((Get-Item $zipFile).Length / 1KB)
        WOK "Downloaded - ${zipSizeKB} KB"
    } else {
        WERR "Download failed!"
        WERR "Try manually: $updateUrl"
        WWRN "Continuing with verification only..."
    }
    
    WHDR 6 $TOTAL "Installing update"
    
    if ($dlOK) {
        if ($_hasUnicode) {
            $extractTemp = "$TEMP_DIR\update-extract"
            New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null
            WINF "Extracting to safe temp..."
            $exOK = Safe-Extract $zipFile $extractTemp
            if ($exOK) {
                $items = Get-ChildItem $extractTemp
                $sourceDir = $extractTemp
                if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $sourceDir = $items[0].FullName }
                WINF "Copying to plugin directory..."
                cmd /c "robocopy `"$sourceDir`" `"$PLUGIN_DIR`" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS /NP" | Out-Null
                $updateApplied = $true
                WOK "Update installed"
            } else {
                WWRN "Temp extract failed, trying direct..."
                $exOK2 = Safe-Extract $zipFile $PLUGIN_DIR
                if ($exOK2) { $updateApplied = $true; WOK "Update installed - direct" }
                else { WERR "All extraction methods failed!" }
            }
        } else {
            WINF "Extracting..."
            $exOK = Safe-Extract $zipFile $PLUGIN_DIR
            if ($exOK) { $updateApplied = $true; WOK "Update installed" }
            else { WERR "All extraction methods failed!" }
        }
    }
} else {
    WHDR 6 $TOTAL "Install update"
    WSKP "No update to install"
}

# Write version.json
if ($updateApplied -and $updateVersion) {
    WINF "Writing version.json..."
    $vj = "{`"version`":`"$updateVersion`"}"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $PLUGIN_DIR "version.json"), $vj, $utf8)
        WOK "version.json -> v$updateVersion"
    } catch {
        try { Set-Content -Path (Join-Path $PLUGIN_DIR "version.json") -Value $vj -Force; WOK "version.json updated" }
        catch { WWRN "Could not write version.json" }
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 7: Python packages health
# ═══════════════════════════════════════════════════════════
WHDR 7 $TOTAL "Python environment"

if (Test-Path $VENV_PY) {
    $ht = Quick-Test $VENV_PY @("-c","import torch,whisper,numpy,librosa; print('OK')")
    if ($ht.OK -and $ht.Out -eq "OK") {
        WSKP "All packages healthy"
    } else {
        WWRN "Some packages need repair..."
        $reqFile = Join-Path $PLUGIN_DIR "requirements.txt"
        if (Test-Path $reqFile) {
            WINF "Reinstalling from requirements.txt..."
            cmd /c "`"$PIP_EXE`" install --isolated -r `"$reqFile`""
            $ht2 = Quick-Test $VENV_PY @("-c","import torch,whisper,numpy,librosa; print('OK')")
            if ($ht2.OK) { WOK "Packages repaired" }
            else { WWRN "Some packages still failing. Run install.ps1 for full repair." }
        }
    }
} else {
    WERR ".venv not found! Run install.ps1 first."
}

# ═══════════════════════════════════════════════════════════
#  STEP 8: Silero VAD
# ═══════════════════════════════════════════════════════════
WHDR 8 $TOTAL "Silero VAD model"

$sileroModel = Join-Path $PLUGIN_DIR "ai_models\silero_vad.onnx"
if (Test-Path $sileroModel) {
    WOK "Silero model present"
    
    # Re-patch if update overwrote
    $detPy = Join-Path $PLUGIN_DIR "speech_detection\silero_detector.py"
    if (Test-Path $detPy) {
        $dc = [System.IO.File]::ReadAllText($detPy, [System.Text.Encoding]::UTF8)
        if ($dc -match "_SILERO_LOCAL|_ONNX_MODEL_LOCAL|_BUNDLED_MODEL") {
            WSKP "silero_detector.py patch intact"
        } elseif ($dc -match '_ONNX_MODEL\s*=\s*os\.path\.join\(_SILERO_CACHE') {
            WINF "Re-patching silero_detector.py..."
            $oldLine = '_ONNX_MODEL = os.path.join(_SILERO_CACHE, "silero_vad.onnx")'
            $patchLines = '_SILERO_LOCAL = os.path.join(' + "`n"
            $patchLines += '    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),' + "`n"
            $patchLines += '    "ai_models", "silero_vad.onnx"' + "`n"
            $patchLines += ')' + "`n"
            $patchLines += '_ONNX_MODEL = _SILERO_LOCAL if os.path.exists(_SILERO_LOCAL) else os.path.join(_SILERO_CACHE, "silero_vad.onnx")'
            $dc = $dc.Replace($oldLine, $patchLines)
            [System.IO.File]::WriteAllText($detPy, $dc, [System.Text.Encoding]::UTF8)
            WOK "silero_detector.py re-patched"
        }
    }
    
    # Ensure model in torch cache
    $cacheDir = Join-Path $env:USERPROFILE ".cache\torch\hub\snakers4_silero-vad_master\src\silero_vad\data"
    $cacheFile = Join-Path $cacheDir "silero_vad.onnx"
    if (-not (Test-Path $cacheFile)) {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        Copy-Item $sileroModel $cacheFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $cacheFile) { WOK "Model copied to cache" }
    }
} else {
    WWRN "Silero model missing from ai_models/"
}

# ═══════════════════════════════════════════════════════════
#  STEP 9: Verification
# ═══════════════════════════════════════════════════════════
WHDR 9 $TOTAL "Verification"

Write-Host ""
$pass = 0; $fail = 0

Write-Host "  --- Plugin Files ---" -ForegroundColor White
foreach ($f in @("index.html","CSXS\manifest.xml","host\premiere.jsx","scripts\backend_server.pyc","scripts\process_video.pyc","version.json","activation-gate.js","requirements.txt","ai_models\silero_vad.onnx","broll-server\server.js")) {
    if (Test-Path (Join-Path $PLUGIN_DIR $f)) { WOK $f; $pass++ }
    else { WERR "$f - MISSING"; $fail++ }
}
if (Test-Path (Join-Path $PLUGIN_DIR "broll-server\node_modules")) { WOK "broll-server/node_modules"; $pass++ }
else { WERR "broll-server/node_modules - MISSING"; $fail++ }

Write-Host ""
Write-Host "  --- Directories ---" -ForegroundColor White
foreach ($d in @("audio_engine","core","scripts","silence_detection","speech_detection","video_engine","waveform_analysis","vendor")) {
    if (Test-Path (Join-Path $PLUGIN_DIR $d)) { WOK $d; $pass++ }
    else { WERR "$d - MISSING"; $fail++ }
}

Write-Host ""
Write-Host "  --- Version ---" -ForegroundColor White
$finalVer = "unknown"
try { $finalVer = (Get-Content (Join-Path $PLUGIN_DIR "version.json") -Raw | ConvertFrom-Json).version } catch {}
if ($updateApplied -and $updateVersion) {
    if ($finalVer -eq $updateVersion) { WOK "Version: v$finalVer - updated from v$currentVer" }
    else { WWRN "Expected v$updateVersion, got v$finalVer" }
} else {
    WOK "Version: v$finalVer"
}

Write-Host ""
Write-Host "  --- Runtime ---" -ForegroundColor White
if (Test-Path $VENV_PY) { WOK ".venv"; $pass++ } else { WERR ".venv missing!"; $fail++ }

$ffCheck = $false
try { $null = Get-Command ffmpeg -ErrorAction Stop; $ffCheck = $true } catch {}
if (-not $ffCheck -and (Test-Path "C:\ffmpeg\ffmpeg.exe")) { $ffCheck = $true }
if ($ffCheck) { WOK "FFmpeg"; $pass++ } else { WWRN "FFmpeg not in PATH" }

$cepOK = $true
foreach ($v in @("9","10","11","12")) {
    $val = (Get-ItemProperty -Path "HKCU:\Software\Adobe\CSXS.$v" -Name "PlayerDebugMode" -ErrorAction SilentlyContinue).PlayerDebugMode
    if ($val -ne "1") { $cepOK = $false }
}
if ($cepOK) { WOK "CEP Debug Mode"; $pass++ } else { WERR "CEP Debug Mode"; $fail++ }

Write-Host ""
Write-Host "  --- Package Imports ---" -ForegroundColor White
if (Test-Path $VENV_PY) {
    foreach ($pkg in @(
        @{N="torch";       C="import torch; print(torch.__version__)"},
        @{N="numpy";       C="import numpy; print(numpy.__version__)"},
        @{N="whisper";     C="import whisper; print(whisper.__version__)"},
        @{N="librosa";     C="import librosa; print(librosa.__version__)"},
        @{N="onnxruntime"; C="import onnxruntime; print(onnxruntime.__version__)"}
    )) {
        $r = Quick-Test $VENV_PY @("-c",$pkg.C)
        if ($r.OK) { WOK "$($pkg.N) $($r.Out)"; $pass++ }
        else { WERR "$($pkg.N) - FAILED"; $fail++ }
    }
}

# Cleanup
try { Remove-Item "$TEMP_DIR\update.zip" -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item "$TEMP_DIR\update-extract" -Recurse -Force -ErrorAction SilentlyContinue } catch {}

# Result
Write-Host ""
$total = $pass + $fail
if ($fail -eq 0) {
    if ($updateApplied) {
        Write-Host "  +=============================================+" -ForegroundColor Green
        Write-Host "  |  [OK] Update successful!                    |" -ForegroundColor Green
        Write-Host "  |  [OK] v$currentVer -> v$updateVersion                          |" -ForegroundColor Green
        Write-Host "  |  [OK] $pass/$total checks passed                     |" -ForegroundColor Green
        Write-Host "  |                                             |" -ForegroundColor Green
        Write-Host "  |  Open Premiere Pro > Extensions > HALEEM    |" -ForegroundColor Green
        Write-Host "  +=============================================+" -ForegroundColor Green
    } else {
        Write-Host "  +=============================================+" -ForegroundColor Green
        Write-Host "  |  [OK] All checks passed!                    |" -ForegroundColor Green
        Write-Host "  |  [OK] Version: v$finalVer                          |" -ForegroundColor Green
        Write-Host "  |  [OK] $pass/$total checks passed                     |" -ForegroundColor Green
        Write-Host "  +=============================================+" -ForegroundColor Green
    }
} elseif ($fail -le 3) {
    Write-Host "  +=============================================+" -ForegroundColor Yellow
    Write-Host "  |  [!!] $pass/$total passed, $fail warnings              |" -ForegroundColor Yellow
    Write-Host "  |  Review warnings above                      |" -ForegroundColor Yellow
    Write-Host "  +=============================================+" -ForegroundColor Yellow
} else {
    Write-Host "  +=============================================+" -ForegroundColor Red
    Write-Host "  |  [XX] $pass/$total passed, $fail failures              |" -ForegroundColor Red
    Write-Host "  |  Run install.ps1 for full repair             |" -ForegroundColor Red
    Write-Host "  +=============================================+" -ForegroundColor Red
}
Write-Host ""
