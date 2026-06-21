# ================================================================
#  HALEEM-ULTRA Installer v4.0 (Pre-built)
#  Downloads pre-built .venv + plugin from Google Drive
#  Only installs external dependencies (Python, Node, FFmpeg, CEP)
# ================================================================

# ─── Helpers ──────────────────────────────────────────────
function WOK  { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function WERR { param([string]$m) Write-Host "  [XX] $m" -ForegroundColor Red }
function WINF { param([string]$m) Write-Host "  [..] $m" -ForegroundColor Gray }
function WWRN { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function WSKP { param([string]$m) Write-Host "  [--] $m" -ForegroundColor DarkGray }
function WHDR { param([int]$n,[int]$t,[string]$m) Write-Host ""; Write-Host "[$n/$t] $m" -ForegroundColor Cyan }

function Manual-Link {
    param([string]$name, [string]$url, [string]$extra)
    Write-Host ""
    Write-Host "  !! $name failed to install automatically." -ForegroundColor Red
    Write-Host "  !! Your system is blocking remote installation." -ForegroundColor Red
    Write-Host ""
    Write-Host "  >> Download manually from:" -ForegroundColor Yellow
    Write-Host "     $url" -ForegroundColor White
    Write-Host ""
    if ($extra) { Write-Host "  >> $extra" -ForegroundColor Gray }
    Write-Host "  >> After installing, run this script again." -ForegroundColor Yellow
    Write-Host ""
}

# ─── Quick-Test ───────────────────────────────────────────
function Quick-Test {
    param([string]$Exe, [string[]]$TestArgs)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $TestArgs -join " "
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $null = $proc.StandardError.ReadToEnd()
        $ok = $proc.WaitForExit(15000)
        if (-not $ok) { $proc.Kill() }
        $out = $stdout.Trim()
        if ($proc.ExitCode -eq 0 -and $out) { return @{OK=$true; Out=$out} }
        return @{OK=$false; Out=$out}
    } catch { return @{OK=$false; Out=""} }
}

# ─── Download with fallbacks ─────────────────────────────
function Safe-Download {
    param([string]$Url, [string]$OutFile, [int]$MinSize = 1000, [switch]$IsGDrive)

    # Already downloaded and valid? Skip
    if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) {
        $sz = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
        WSKP "Already downloaded - ${sz}MB"
        return $true
    }
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }

    # Method 1: curl.exe (fastest, best for Google Drive)
    try {
        $curlExe = "C:\Windows\System32\curl.exe"
        if (Test-Path $curlExe) {
            WINF "Downloading via curl..."
            if ($IsGDrive) {
                cmd /c "`"$curlExe`" -L -o `"$OutFile`" -# -b `"NID=1`" `"$Url`""
            } else {
                cmd /c "`"$curlExe`" -L -o `"$OutFile`" -# `"$Url`""
            }
            if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
            WINF "curl result too small, trying next..."
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        }
    } catch { WINF "curl failed, trying next..." }

    # Method 2: WebClient (sync)
    try {
        WINF "Downloading via WebClient..."
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "HALEEM-ULTRA-Installer/4.0")
        if ($IsGDrive) { $wc.Headers.Add("Cookie", "NID=1") }
        $wc.DownloadFile($Url, $OutFile)
        $wc.Dispose()
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "WebClient failed, trying next..." }

    # Method 3: Invoke-WebRequest
    try {
        WINF "Downloading via IWR..."
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "IWR failed, trying next..." }

    # Method 4: BitsTransfer
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        WINF "Downloading via BITS..."
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        Start-BitsTransfer -Source $Url -Destination $OutFile
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "BITS failed..." }

    return $false
}

# ═══════════════════════════════════════════════════════════
#  PRE-FLIGHT
# ═══════════════════════════════════════════════════════════
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    WERR "Run as Administrator! Right-click PowerShell -> Run as Administrator"
    return
}

$TOTAL = 7

Write-Host ""
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host "  |  HALEEM-ULTRA  Installer v4.0 (Pre-built)   |" -ForegroundColor Magenta
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host ""
Write-Host "  User:    $env:USERNAME" -ForegroundColor Gray
Write-Host "  Profile: $env:USERPROFILE" -ForegroundColor Gray
Write-Host "  OS:      $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "  PS:      $($PSVersionTable.PSVersion)" -ForegroundColor Gray

# ─── Paths ────────────────────────────────────────────────
$EXT_DIR   = Join-Path $env:APPDATA "Adobe\CEP\extensions"
$PLUG_DIR  = Join-Path $EXT_DIR "com.haleem.ultra.client"
$VENV_DIR  = Join-Path $EXT_DIR ".venv"
$TEMP_DIR  = "C:\haleem-temp"
$NODE_VER  = "22.16.0"
$GDRIVE_ID = "1JG6SUo6P_YE3kJKEBV3d11-QFOBUEGqQ"
$GDRIVE_URL = "https://drive.usercontent.google.com/download?id=$GDRIVE_ID&export=download&authuser=0&confirm=t"

if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null }
if (-not (Test-Path $EXT_DIR)) { New-Item -ItemType Directory -Path $EXT_DIR -Force | Out-Null }

# ═══════════════════════════════════════════════════════════
#  STEP 1: Python 3.11
# ═══════════════════════════════════════════════════════════
WHDR 1 $TOTAL "Python 3.11"

$PY_EXE = ""
$pyOK = $false

# Check known install paths
foreach ($p in @(
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "C:\Python311\python.exe",
    "C:\Program Files\Python311\python.exe",
    "C:\Program Files (x86)\Python311\python.exe"
)) {
    if (Test-Path $p) {
        $t = Quick-Test $p @("--version")
        if ($t.OK) { $PY_EXE = $p; WOK "Python OK: $($t.Out)"; $pyOK = $true; break }
    }
}

# Check PATH
if (-not $pyOK) {
    try {
        $pc = Get-Command python -ErrorAction Stop
        $t = Quick-Test $pc.Source @("--version")
        if ($t.OK -and $t.Out -match "3\.1[0-9]") { $PY_EXE = $pc.Source; WOK "Python in PATH: $($t.Out)"; $pyOK = $true }
    } catch {}
}

# Check py launcher
if (-not $pyOK) {
    try {
        $py = Get-Command py -ErrorAction Stop
        $t = Quick-Test $py.Source @("-3","--version")
        if ($t.OK) { $PY_EXE = $py.Source; WOK "Python via py launcher: $($t.Out)"; $pyOK = $true }
    } catch {}
}

if (-not $pyOK) {
    $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    $pyInst = "$TEMP_DIR\python-installer.exe"

    WINF "Downloading Python 3.11.9..."
    $dlOK = Safe-Download $pyUrl $pyInst 20000000

    if ($dlOK) {
        # Attempt 1: Install to C:\Python311 (safe ASCII path)
        WINF "Installing Python (attempt 1: C:\Python311)..."
        $pyProc = Start-Process -FilePath $pyInst -ArgumentList "/quiet","InstallAllUsers=1","PrependPath=0","Include_pip=1","Include_test=0","TargetDir=C:\Python311" -PassThru -NoNewWindow
        $null = $pyProc.WaitForExit(300000)
        Start-Sleep -Seconds 3

        foreach ($alt in @("C:\Python311\python.exe","$env:LOCALAPPDATA\Programs\Python\Python311\python.exe","C:\Program Files\Python311\python.exe")) {
            if (Test-Path $alt) {
                $t = Quick-Test $alt @("--version")
                if ($t.OK) { $PY_EXE = $alt; WOK "Python installed: $($t.Out)"; $pyOK = $true; break }
            }
        }

        # Attempt 2: Default install
        if (-not $pyOK) {
            WWRN "Attempt 1 failed. Trying default install..."
            $pyProc2 = Start-Process -FilePath $pyInst -ArgumentList "/quiet","InstallAllUsers=1","PrependPath=1","Include_pip=1" -PassThru -NoNewWindow
            $null = $pyProc2.WaitForExit(300000)
            Start-Sleep -Seconds 5

            foreach ($alt in @("C:\Program Files\Python311\python.exe","$env:LOCALAPPDATA\Programs\Python\Python311\python.exe","C:\Python311\python.exe")) {
                if (Test-Path $alt) {
                    $t = Quick-Test $alt @("--version")
                    if ($t.OK) { $PY_EXE = $alt; WOK "Python installed: $($t.Out)"; $pyOK = $true; break }
                }
            }
        }

        # Attempt 3: Interactive install (user sees GUI)
        if (-not $pyOK) {
            WWRN "Silent install failed. Opening installer GUI..."
            $pyProc3 = Start-Process -FilePath $pyInst -PassThru
            WINF "Please install Python manually in the window that opened."
            WINF "IMPORTANT: Check 'Add to PATH' option!"
            $null = $pyProc3.WaitForExit(600000)
            Start-Sleep -Seconds 3

            # Re-scan
            foreach ($alt in @("C:\Python311\python.exe","C:\Program Files\Python311\python.exe","$env:LOCALAPPDATA\Programs\Python\Python311\python.exe")) {
                if (Test-Path $alt) {
                    $t = Quick-Test $alt @("--version")
                    if ($t.OK) { $PY_EXE = $alt; WOK "Python installed: $($t.Out)"; $pyOK = $true; break }
                }
            }
        }
    }

    if (-not $pyOK) {
        Manual-Link "Python 3.11" "https://www.python.org/downloads/release/python-3119/" "Choose 'Windows installer (64-bit)' and check 'Add to PATH'"
        return
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 2: Node.js
# ═══════════════════════════════════════════════════════════
WHDR 2 $TOTAL "Node.js"

$NODE_EXE = "C:\Program Files\nodejs\node.exe"
$nodeOK = $false

if (Test-Path $NODE_EXE) {
    $nv = Quick-Test $NODE_EXE @("--version")
    if ($nv.OK) { WOK "Node.js OK: $($nv.Out)"; $nodeOK = $true }
}
if (-not $nodeOK) {
    try { $nc = Get-Command node -ErrorAction Stop; $NODE_EXE = $nc.Source; WOK "Node.js in PATH: $NODE_EXE"; $nodeOK = $true } catch {}
}

if (-not $nodeOK) {
    $nodeUrl = "https://nodejs.org/dist/v$NODE_VER/node-v$NODE_VER-x64.msi"
    $nodeInst = "$TEMP_DIR\node-installer.msi"

    WINF "Downloading Node.js v$NODE_VER..."
    $dlOK = Safe-Download $nodeUrl $nodeInst 20000000

    if ($dlOK) {
        # Attempt 1: Silent MSI
        WINF "Installing Node.js (silent)..."
        $msiProc = Start-Process msiexec.exe -ArgumentList "/i `"$nodeInst`" /quiet /norestart" -PassThru -NoNewWindow
        $waited = $msiProc.WaitForExit(120000)
        if (-not $waited) { try { $msiProc.Kill() } catch {} }
        Start-Sleep -Seconds 3

        if (Test-Path "C:\Program Files\nodejs\node.exe") {
            $NODE_EXE = "C:\Program Files\nodejs\node.exe"; WOK "Node.js installed"; $nodeOK = $true
        }

        # Attempt 2: Interactive MSI
        if (-not $nodeOK) {
            WWRN "Silent install failed. Opening installer..."
            $msiProc2 = Start-Process msiexec.exe -ArgumentList "/i `"$nodeInst`"" -PassThru
            WINF "Please install Node.js in the window that opened."
            $null = $msiProc2.WaitForExit(600000)
            Start-Sleep -Seconds 3
            if (Test-Path "C:\Program Files\nodejs\node.exe") {
                $NODE_EXE = "C:\Program Files\nodejs\node.exe"; WOK "Node.js installed"; $nodeOK = $true
            }
        }
    }

    if (-not $nodeOK) {
        Manual-Link "Node.js" "https://nodejs.org/en/download/" "Download the Windows Installer (.msi) 64-bit"
        return
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 3: FFmpeg
# ═══════════════════════════════════════════════════════════
WHDR 3 $TOTAL "FFmpeg"

$ffOK = $false
try { $null = Get-Command ffmpeg -ErrorAction Stop; WOK "FFmpeg already installed"; $ffOK = $true } catch {}
if (-not $ffOK -and (Test-Path "C:\ffmpeg\ffmpeg.exe")) {
    $env:PATH = "C:\ffmpeg;$env:PATH"
    WOK "FFmpeg at C:\ffmpeg"; $ffOK = $true
}

if (-not $ffOK) {
    # Attempt 1: winget
    WINF "Trying winget..."
    try {
        $wg = Get-Command winget -ErrorAction Stop
        cmd /c "winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements --silent" 2>$null
        Start-Sleep -Seconds 3
        try { $null = Get-Command ffmpeg -ErrorAction Stop; WOK "FFmpeg installed via winget"; $ffOK = $true } catch {}
    } catch { WINF "winget not available" }

    # Attempt 2: Download manually
    if (-not $ffOK) {
        WINF "Downloading FFmpeg..."
        $ffUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        $ffZip = "$TEMP_DIR\ffmpeg.zip"
        $dlOK = Safe-Download $ffUrl $ffZip 30000000

        if ($dlOK) {
            WINF "Extracting FFmpeg..."
            $ffExtract = "$TEMP_DIR\ffmpeg-extract"
            if (Test-Path $ffExtract) { Remove-Item $ffExtract -Recurse -Force -ErrorAction SilentlyContinue }
            try { Expand-Archive -Path $ffZip -DestinationPath $ffExtract -Force } catch {}
            $ffBin = Get-ChildItem $ffExtract -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ffBin) {
                if (-not (Test-Path "C:\ffmpeg")) { New-Item -ItemType Directory -Path "C:\ffmpeg" -Force | Out-Null }
                Copy-Item $ffBin.FullName "C:\ffmpeg\ffmpeg.exe" -Force
                $ffprobe = Join-Path $ffBin.DirectoryName "ffprobe.exe"
                if (Test-Path $ffprobe) { Copy-Item $ffprobe "C:\ffmpeg\ffprobe.exe" -Force }
                $env:PATH = "C:\ffmpeg;$env:PATH"
                [System.Environment]::SetEnvironmentVariable("PATH", "C:\ffmpeg;" + [System.Environment]::GetEnvironmentVariable("PATH","Machine"), "Machine")
                WOK "FFmpeg installed to C:\ffmpeg"
                $ffOK = $true
            }
        }
    }

    if (-not $ffOK) {
        Manual-Link "FFmpeg" "https://www.gyan.dev/ffmpeg/builds/" "Download 'ffmpeg-release-essentials.zip', extract, copy ffmpeg.exe to C:\ffmpeg\"
        # Don't return - FFmpeg is optional, continue
        WWRN "Continuing without FFmpeg - some features may not work"
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 4: CEP Debug Mode
# ═══════════════════════════════════════════════════════════
WHDR 4 $TOTAL "CEP Debug Mode"

$cepChanged = $false
foreach ($v in @("9","10","11","12")) {
    $regPath = "HKCU:\Software\Adobe\CSXS.$v"
    $val = (Get-ItemProperty -Path $regPath -Name "PlayerDebugMode" -ErrorAction SilentlyContinue).PlayerDebugMode
    if ($val -ne "1") {
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "PlayerDebugMode" -Value "1" -Type String
        $cepChanged = $true
    }
}
if ($cepChanged) { WOK "CEP debug mode enabled" }
else { WSKP "CEP debug mode already enabled" }

# ═══════════════════════════════════════════════════════════
#  STEP 5: Download Plugin Package from Google Drive
# ═══════════════════════════════════════════════════════════
WHDR 5 $TOTAL "Download plugin package"

$needDownload = $true

# Check if already fully installed
if ((Test-Path $PLUG_DIR) -and (Test-Path $VENV_DIR)) {
    $plugFiles = (Get-ChildItem $PLUG_DIR -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    $venvPy = Join-Path $VENV_DIR "Scripts\python.exe"
    if ($plugFiles -gt 4000 -and (Test-Path $venvPy)) {
        # Verify .venv actually works
        $venvScripts = Split-Path $venvPy
        $testOut = cmd /c "set PATH=$venvScripts;%PATH% && `"$venvPy`" -c `"print('OK')`"" 2>$null
        if ($LASTEXITCODE -eq 0 -and $testOut -match "OK") {
            WSKP "Plugin and .venv already installed and working"
            $needDownload = $false
        } else {
            WWRN "Plugin exists but .venv is broken. Re-downloading..."
        }
    }
}

if ($needDownload) {
    $zipFile = "$TEMP_DIR\haleem-ultra-complete.zip"

    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Yellow
    Write-Host "  |  Downloading HALEEM-ULTRA package (~2.7 GB)  |" -ForegroundColor Yellow
    Write-Host "  |  This will take several minutes...           |" -ForegroundColor Yellow
    Write-Host "  ==============================================" -ForegroundColor Yellow
    Write-Host ""

    $dlOK = Safe-Download $GDRIVE_URL $zipFile 100000000 -IsGDrive

    if (-not $dlOK) {
        WERR "Download failed!"
        Manual-Link "HALEEM-ULTRA Package" "https://drive.google.com/file/d/$GDRIVE_ID/view" "Download the ZIP, then extract both folders to: $EXT_DIR"
        return
    }

    $zipSizeMB = [math]::Round((Get-Item $zipFile).Length / 1MB, 1)
    WOK "Downloaded: ${zipSizeMB} MB"

    # ═══════════════════════════════════════════════════════════
    #  STEP 6: Extract and install
    # ═══════════════════════════════════════════════════════════
    WHDR 6 $TOTAL "Extract and install"

    # Remove old installation (use rd /s /q for long paths)
    if (Test-Path $PLUG_DIR) {
        WINF "Removing old plugin..."
        cmd /c "rd /s /q `"$PLUG_DIR`"" 2>$null
        if (Test-Path $PLUG_DIR) { Remove-Item $PLUG_DIR -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path $VENV_DIR) {
        WINF "Removing old .venv..."
        Get-Process python* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $vi = Get-Item $VENV_DIR -Force -ErrorAction SilentlyContinue
        if ($vi -and ($vi.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            cmd /c "rmdir `"$VENV_DIR`"" | Out-Null
        } else {
            cmd /c "rd /s /q `"$VENV_DIR`"" 2>$null
            Start-Sleep -Seconds 1
            if (Test-Path $VENV_DIR) {
                WINF "Retrying delete..."
                cmd /c "rd /s /q `"$VENV_DIR`"" 2>$null
            }
        }
    }

    WINF "Extracting package..."

    $extractOK = $false

    # Method 1: tar.exe (FASTEST - built into Windows 10+)
    if (Test-Path "C:\Windows\System32\tar.exe") {
        WINF "Extracting via tar (fast)..."
        try {
            Push-Location $EXT_DIR
            cmd /c "tar.exe -xf `"$zipFile`""
            if ($LASTEXITCODE -eq 0) { $extractOK = $true; WOK "Extracted via tar" }
            Pop-Location
        } catch { try { Pop-Location } catch {}; WINF "tar failed, trying next..." }
    }

    # Method 2: 7-Zip (fast if installed)
    if (-not $extractOK) {
        $7z = "C:\Program Files\7-Zip\7z.exe"
        if (Test-Path $7z) {
            WINF "Extracting via 7-Zip..."
            cmd /c "`"$7z`" x `"$zipFile`" -o`"$EXT_DIR`" -y" | Out-Null
            if ($LASTEXITCODE -eq 0) { $extractOK = $true; WOK "Extracted via 7-Zip" }
        }
    }

    # Method 3: .NET ZipFile
    if (-not $extractOK) {
        WINF "Extracting via .NET (slower)..."
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $EXT_DIR)
            $extractOK = $true
            WOK "Extracted via .NET"
        } catch { WINF ".NET failed, trying Expand-Archive..." }
    }

    # Method 4: Expand-Archive (slowest - last resort)
    if (-not $extractOK) {
        WINF "Extracting via Expand-Archive (this may be slow)..."
        try {
            Expand-Archive -Path $zipFile -DestinationPath $EXT_DIR -Force
            $extractOK = $true
            WOK "Extracted via Expand-Archive"
        } catch { WINF "Expand-Archive failed" }
    }

    if (-not $extractOK) {
        WERR "Extraction failed!"
        WINF "Please extract manually:"
        WINF "  File: $zipFile"
        WINF "  Extract to: $EXT_DIR"
        return
    }

    # Delete ZIP
    WINF "Cleaning up ZIP..."
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    WOK "ZIP removed - saved $zipSizeMB MB"
} else {
    WHDR 6 $TOTAL "Extract and install"
    WSKP "Already installed - skipping"
}

# ═══════════════════════════════════════════════════════════
#  STEP 7: Silero VAD Cache
# ═══════════════════════════════════════════════════════════
WHDR 7 $TOTAL "Silero VAD cache"

$silero = Join-Path $PLUG_DIR "ai_models\silero_vad.onnx"
if (Test-Path $silero) {
    $cacheDir = Join-Path $env:USERPROFILE ".cache\torch\hub\snakers4_silero-vad_master\src\silero_vad\data"
    $cacheFile = Join-Path $cacheDir "silero_vad.onnx"
    if (-not (Test-Path $cacheFile)) {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        Copy-Item $silero $cacheFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $cacheFile) { WOK "Model copied to cache" }
        else { WWRN "Could not copy model to cache" }
    } else { WSKP "Model cache exists" }
} else { WWRN "Silero model not found in plugin" }

# Patch silero_detector.py if needed
$det = Join-Path $PLUG_DIR "speech_detection\silero_detector.py"
if (Test-Path $det) {
    $dc = [System.IO.File]::ReadAllText($det, [System.Text.Encoding]::UTF8)
    if ($dc -match "_SILERO_LOCAL|_ONNX_MODEL_LOCAL|_BUNDLED_MODEL") {
        WSKP "silero_detector already patched"
    } elseif ($dc -match '_ONNX_MODEL\s*=\s*os\.path\.join\(_SILERO_CACHE') {
        WINF "Patching silero_detector.py..."
        $old = '_ONNX_MODEL = os.path.join(_SILERO_CACHE, "silero_vad.onnx")'
        $new = @'
_SILERO_LOCAL = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "ai_models", "silero_vad.onnx"
)
_ONNX_MODEL = _SILERO_LOCAL if os.path.exists(_SILERO_LOCAL) else os.path.join(_SILERO_CACHE, "silero_vad.onnx")
'@
        $dc = $dc.Replace($old, $new)
        [System.IO.File]::WriteAllText($det, $dc, [System.Text.Encoding]::UTF8)
        WOK "Patched"
    }
}

# ═══════════════════════════════════════════════════════════
#  FINAL VERIFICATION
# ═══════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  ==============================================" -ForegroundColor Cyan
Write-Host "  |  Final Verification                         |" -ForegroundColor Cyan
Write-Host "  ==============================================" -ForegroundColor Cyan

$pass = 0
$fail = 0

# Plugin files
Write-Host ""
Write-Host "  --- Plugin Files ---" -ForegroundColor White
foreach ($f in @("index.html","CSXS\manifest.xml","host\premiere.jsx","scripts\backend_server.pyc","scripts\process_video.pyc","version.json","activation-gate.js","requirements.txt","ai_models\silero_vad.onnx","broll-server\server.js")) {
    if (Test-Path (Join-Path $PLUG_DIR $f)) { WOK $f; $pass++ }
    else { WERR "$f MISSING"; $fail++ }
}

if (Test-Path (Join-Path $PLUG_DIR "broll-server\node_modules")) { WOK "node_modules"; $pass++ }
else { WERR "node_modules MISSING"; $fail++ }

# Runtime
Write-Host ""
Write-Host "  --- Runtime ---" -ForegroundColor White
if ($pyOK) { WOK "Python"; $pass++ } else { WERR "Python"; $fail++ }

$VENV_PY = Join-Path $VENV_DIR "Scripts\python.exe"
if (Test-Path $VENV_PY) { WOK ".venv"; $pass++ } else { WERR ".venv MISSING"; $fail++ }
if ($nodeOK) { WOK "Node.js"; $pass++ } else { WWRN "Node.js" }
if ($ffOK) { WOK "FFmpeg"; $pass++ } else { WWRN "FFmpeg" }

$cepOK2 = $true
foreach ($v in @("9","10","11","12")) {
    $val = (Get-ItemProperty -Path "HKCU:\Software\Adobe\CSXS.$v" -Name "PlayerDebugMode" -ErrorAction SilentlyContinue).PlayerDebugMode
    if ($val -ne "1") { $cepOK2 = $false }
}
if ($cepOK2) { WOK "CEP Debug"; $pass++ } else { WERR "CEP Debug"; $fail++ }

# Package imports
Write-Host ""
Write-Host "  --- Package Imports ---" -ForegroundColor White
$venvScripts = Split-Path $VENV_PY
foreach ($pkg in @(
    @{N="torch";       C="import torch; print(torch.__version__)"},
    @{N="torchaudio";  C="import torchaudio; print(torchaudio.__version__)"},
    @{N="numpy";       C="import numpy; print(numpy.__version__)"},
    @{N="scipy";       C="import scipy; print(scipy.__version__)"},
    @{N="librosa";     C="import librosa; print(librosa.__version__)"},
    @{N="soundfile";   C="import soundfile; print(soundfile.__version__)"},
    @{N="whisper";     C="import whisper; print(whisper.__version__)"},
    @{N="onnxruntime"; C="import onnxruntime; print(onnxruntime.__version__)"},
    @{N="pydantic";    C="import pydantic; print(pydantic.__version__)"}
)) {
    $ver = cmd /c "set PATH=$venvScripts;%PATH% && `"$VENV_PY`" -c `"$($pkg.C)`"" 2>$null
    if ($LASTEXITCODE -eq 0 -and $ver) { WOK "$($pkg.N) $ver"; $pass++ }
    else { WERR "$($pkg.N) FAILED"; $fail++ }
}

# Summary
Write-Host ""
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  +=============================================+" -ForegroundColor Green
    Write-Host "  |  ALL $total/$total checks passed!                    |" -ForegroundColor Green
    Write-Host "  |  Restart Premiere Pro to use HALEEM-ULTRA   |" -ForegroundColor Green
    Write-Host "  +=============================================+" -ForegroundColor Green
} else {
    Write-Host "  +=============================================+" -ForegroundColor Red
    Write-Host "  |  $pass/$total passed, $fail failures                    |" -ForegroundColor Red
    Write-Host "  |  Contact support with screenshot            |" -ForegroundColor Red
    Write-Host "  +=============================================+" -ForegroundColor Red
}

# Clean temp
Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
