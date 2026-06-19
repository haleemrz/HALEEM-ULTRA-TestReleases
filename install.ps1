<#
.SYNOPSIS
    HALEEM-ULTRA — Bulletproof Installer v3.0
.DESCRIPTION
    Installs HALEEM-ULTRA plugin with ALL dependencies.
    Works on ALL machines including Arabic/Unicode usernames.
    
    Run as Administrator in PowerShell:
    Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/haleemrz/HALEEM-ULTRA-TestReleases/master/install.ps1 | iex
#>

# ═══════════════════════════════════════════════════════════
#  INIT — Safe for irm | iex on PowerShell 5.1
# ═══════════════════════════════════════════════════════════
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ─── Helpers (simple functions, no complex syntax) ────────
function WOK  { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function WWRN { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function WERR { param([string]$m) Write-Host "  [XX] $m" -ForegroundColor Red }
function WINF { param([string]$m) Write-Host "  [..] $m" -ForegroundColor Cyan }
function WHDR { param([int]$n,[int]$t,[string]$m) Write-Host "`n[$n/$t] $m" -ForegroundColor Cyan }

# ─── Safe download function (4 methods) ──────────────────
function Safe-Download {
    param([string]$Url, [string]$OutFile, [int]$MinSize = 1000)
    
    # Method 1: WebClient
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "HALEEM-ULTRA-Installer/3.0")
        $wc.DownloadFile($Url, $OutFile)
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "WebClient failed, trying next..." }
    
    # Method 2: Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -UserAgent "HALEEM-ULTRA-Installer/3.0"
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
        Start-BitsTransfer -Source $Url -Destination $OutFile -Description "HALEEM-ULTRA"
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "BitsTransfer failed" }
    
    return $false
}

# ─── Safe extract function (5 methods) ───────────────────
function Safe-Extract {
    param([string]$ZipFile, [string]$DestDir)
    
    # Method 1: Expand-Archive
    try {
        Expand-Archive -Path $ZipFile -DestinationPath $DestDir -Force
        return $true
    } catch { WINF "Expand-Archive failed, trying next..." }
    
    # Method 2: .NET ZipFile manual entry-by-entry (most reliable)
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

# ─── Safe command runner (captures errors without breaking iex) ──
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
#  STEP 0: Pre-flight checks
# ═══════════════════════════════════════════════════════════
$TOTAL_STEPS = 12

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    WERR "Run as Administrator! Right-click PowerShell -> Run as Administrator"
    WERR "يجب تشغيل PowerShell كمسؤول"
    return
}

# Detect Unicode/Arabic username
$_hasUnicode = $env:USERPROFILE -match '[^\x00-\x7F]'
$_hasSpaces  = $env:USERPROFILE -match ' '

Write-Host ""
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host "  |  HALEEM-ULTRA  Installer v3.0 (Bulletproof) |" -ForegroundColor Magenta
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host ""
Write-Host "  User:    $env:USERNAME" -ForegroundColor Gray
Write-Host "  Profile: $env:USERPROFILE" -ForegroundColor Gray
Write-Host "  OS:      $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "  PS:      $($PSVersionTable.PSVersion)" -ForegroundColor Gray
if ($_hasUnicode) { WWRN "Arabic/Unicode username detected — using safe paths" }
if ($_hasSpaces)  { WWRN "Spaces in profile path detected" }
Write-Host ""

# ═══════════════════════════════════════════════════════════
#  Configuration (Unicode-safe from the start)
# ═══════════════════════════════════════════════════════════
$REPO_OWNER     = "haleemrz"
$REPO_NAME      = "HALEEM-ULTRA-Releases"
$PYTHON_VERSION = "3.11.9"
$NODE_VERSION   = "25.2.1"

# Safe paths (no Arabic, no spaces)
if ($_hasUnicode -or $_hasSpaces) {
    $PYTHON_DIR  = "C:\Python311"
    $SAFE_VENV   = "C:\haleem-venv"
    $SAFE_FFMPEG = "C:\ffmpeg"
    $TEMP_DIR    = "C:\haleem-temp"
} else {
    $PYTHON_DIR  = "$env:LOCALAPPDATA\Programs\Python\Python311"
    $SAFE_VENV   = ""
    $SAFE_FFMPEG = ""
    $TEMP_DIR    = "$env:TEMP\haleem-ultra-install"
}

$PYTHON_EXE  = "$PYTHON_DIR\python.exe"
$EXT_DIR     = Join-Path $env:APPDATA "Adobe\CEP\extensions"
$PLUGIN_DIR  = Join-Path $EXT_DIR "com.haleem.ultra.client"
$VENV_DIR    = Join-Path $EXT_DIR ".venv"
$PIP_EXE     = Join-Path $VENV_DIR "Scripts\pip.exe"
$VENV_PY     = Join-Path $VENV_DIR "Scripts\python.exe"

# Auto-detect latest full release
$PLUGIN_VERSION = "2.8"
$PLUGIN_ZIP_URL = ""
try {
    $apiUrl = "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases?per_page=10"
    $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    foreach ($rel in $releases) {
        $zipAsset = $rel.assets | Where-Object { $_.name -match '^haleem-ultra-v.*\.zip$' } | Select-Object -First 1
        if ($zipAsset) {
            $PLUGIN_VERSION = $rel.tag_name -replace '^v', ''
            $PLUGIN_ZIP_URL = $zipAsset.browser_download_url
            break
        }
    }
} catch { WINF "Could not auto-detect version, using fallback" }
if (-not $PLUGIN_ZIP_URL) {
    $PLUGIN_ZIP_URL = "https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/v${PLUGIN_VERSION}/haleem-ultra-v${PLUGIN_VERSION}.zip"
}

# Package versions
$TORCH_INDEX = "https://download.pytorch.org/whl/cu121"
$TORCH_PKGS  = @("torch==2.5.1+cu121", "torchaudio==2.5.1+cu121")
$PIP_PKGS    = @(
    "numpy==2.4.5", "scipy==1.17.1", "soundfile==0.13.1",
    "librosa==0.11.0", "tqdm==4.67.3", "pydantic==2.13.4",
    "onnxruntime==1.26.0", "openai-whisper==20250625"
)

# Prep temp
if (Test-Path $TEMP_DIR) { Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

# ═══════════════════════════════════════════════════════════
#  STEP 1: Python 3.11
# ═══════════════════════════════════════════════════════════
WHDR 1 $TOTAL_STEPS "Python $PYTHON_VERSION"

$needPython = $true

# Check multiple candidate locations
$pyCandidates = @(
    $PYTHON_EXE,
    "C:\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "C:\Program Files\Python311\python.exe",
    "C:\Python312\python.exe"
)
foreach ($pyc in $pyCandidates) {
    if (Test-Path $pyc) {
        $pyVer = Safe-Run $pyc @("--version")
        if ($pyVer.Output -match "3\.11") {
            $PYTHON_EXE = $pyc
            $PYTHON_DIR = Split-Path $pyc
            WOK "Python found: $($pyVer.Output.Trim()) at $PYTHON_DIR"
            $needPython = $false
            break
        }
    }
}

if ($needPython) {
    $pyUrl = "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-amd64.exe"
    $pyInstaller = "$TEMP_DIR\python-installer.exe"
    
    WINF "Downloading Python $PYTHON_VERSION..."
    $dlOK = Safe-Download $pyUrl $pyInstaller 20000000
    if (-not $dlOK) {
        WERR "Failed to download Python. Check internet connection."
        WERR "Manual download: $pyUrl"
        return
    }
    
    # Attempt 1: Install to safe path
    WINF "Installing Python to $PYTHON_DIR..."
    $installArgs = "/quiet InstallAllUsers=1 PrependPath=0 Include_pip=1 Include_test=0 TargetDir=$PYTHON_DIR"
    $pyResult = Safe-Run $pyInstaller $installArgs.Split(" ")
    # Wait for installer to finish
    Start-Sleep -Seconds 5
    
    if (Test-Path $PYTHON_EXE) {
        $pyVer = Safe-Run $PYTHON_EXE @("--version")
        WOK "Python installed: $($pyVer.Output.Trim())"
    } else {
        # Attempt 2: Default all-users
        WWRN "First attempt failed, retrying with default location..."
        $installArgs2 = "/quiet InstallAllUsers=1 PrependPath=0 Include_pip=1"
        Safe-Run $pyInstaller $installArgs2.Split(" ") | Out-Null
        Start-Sleep -Seconds 5
        
        # Check alternate locations
        $altPaths = @("C:\Program Files\Python311\python.exe", "C:\Python311\python.exe")
        $foundAlt = $false
        foreach ($alt in $altPaths) {
            if (Test-Path $alt) {
                $PYTHON_EXE = $alt
                $PYTHON_DIR = Split-Path $alt
                WOK "Python installed at $PYTHON_DIR"
                $foundAlt = $true
                break
            }
        }
        if (-not $foundAlt) {
            # Attempt 3: User install (no admin needed for TargetDir)
            WWRN "Trying user install..."
            $userPyDir = "$env:LOCALAPPDATA\Programs\Python\Python311"
            $installArgs3 = "/quiet InstallAllUsers=0 PrependPath=0 Include_pip=1 TargetDir=$userPyDir"
            Safe-Run $pyInstaller $installArgs3.Split(" ") | Out-Null
            Start-Sleep -Seconds 5
            
            if (Test-Path "$userPyDir\python.exe") {
                $PYTHON_EXE = "$userPyDir\python.exe"
                $PYTHON_DIR = $userPyDir
                WOK "Python installed at $PYTHON_DIR"
            } else {
                WERR "Python installation failed after 3 attempts!"
                WERR "Install manually from: https://www.python.org/downloads/"
                WERR "IMPORTANT: Install to C:\Python311"
                return
            }
        }
    }
}

# Verify Python works
$pyTest = Safe-Run $PYTHON_EXE @("-c", "print('OK')")
if ($pyTest.Output.Trim() -ne "OK") {
    WERR "Python installed but not working correctly"
    return
}

# ═══════════════════════════════════════════════════════════
#  STEP 2: Node.js
# ═══════════════════════════════════════════════════════════
WHDR 2 $TOTAL_STEPS "Node.js v$NODE_VERSION"

$NODE_EXE = "C:\Program Files\nodejs\node.exe"
$nodeOK = $false

if (Test-Path $NODE_EXE) {
    $nv = Safe-Run $NODE_EXE @("--version")
    WOK "Node.js already installed: $($nv.Output.Trim())"
    $nodeOK = $true
} else {
    # Check PATH
    try {
        $nodeCmd = Get-Command node -ErrorAction Stop
        $NODE_EXE = $nodeCmd.Source
        WOK "Node.js found in PATH: $NODE_EXE"
        $nodeOK = $true
    } catch {}
}

if (-not $nodeOK) {
    $nodeUrl = "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-x64.msi"
    $nodeInstaller = "$TEMP_DIR\node-installer.msi"
    
    WINF "Downloading Node.js v$NODE_VERSION..."
    $dlOK = Safe-Download $nodeUrl $nodeInstaller 20000000
    if ($dlOK) {
        WINF "Installing Node.js..."
        $msiArgs = "/i `"$nodeInstaller`" /quiet /norestart"
        Start-Process msiexec.exe -ArgumentList $msiArgs.Split(" ") -Wait -NoNewWindow
        Start-Sleep -Seconds 3
        
        if (Test-Path "C:\Program Files\nodejs\node.exe") {
            $NODE_EXE = "C:\Program Files\nodejs\node.exe"
            WOK "Node.js installed"
        } else {
            WWRN "Node.js install may need a restart"
        }
    } else {
        WWRN "Node.js download failed. broll-server may not work."
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 3: FFmpeg (critical for pipeline)
# ═══════════════════════════════════════════════════════════
WHDR 3 $TOTAL_STEPS "FFmpeg"

$ffmpegPath = $null
$ffmpegOK = $false

# Search for ffmpeg in multiple locations
$ffCandidates = @(
    "C:\ffmpeg\ffmpeg.exe",
    "C:\ffmpeg\bin\ffmpeg.exe",
    "$env:APPDATA\HappyDuckAI\ffmpeg\ffmpeg.exe",
    "$PLUGIN_DIR\ffmpeg.exe",
    "C:\ProgramData\chocolatey\bin\ffmpeg.exe"
)

# Check PATH first
try {
    $ffCmd = Get-Command ffmpeg -ErrorAction Stop
    $ffmpegPath = $ffCmd.Source
} catch {}

# Check candidate locations
if (-not $ffmpegPath) {
    foreach ($fc in $ffCandidates) {
        if (Test-Path $fc) { $ffmpegPath = $fc; break }
    }
}

if ($ffmpegPath) {
    # Check if in Unicode path
    $ffInUnicode = "$ffmpegPath" -match '[^\x00-\x7F]'
    
    if ($ffInUnicode) {
        WWRN "FFmpeg in Unicode path: $ffmpegPath"
        WINF "Copying to safe path: C:\ffmpeg"
        
        $ffSrcDir = Split-Path $ffmpegPath
        if (-not (Test-Path "C:\ffmpeg")) { New-Item -ItemType Directory -Path "C:\ffmpeg" -Force | Out-Null }
        
        Copy-Item (Join-Path $ffSrcDir "ffmpeg.exe") "C:\ffmpeg\ffmpeg.exe" -Force -ErrorAction SilentlyContinue
        $ffprobeSrc = Join-Path $ffSrcDir "ffprobe.exe"
        if (Test-Path $ffprobeSrc) { Copy-Item $ffprobeSrc "C:\ffmpeg\ffprobe.exe" -Force -ErrorAction SilentlyContinue }
        
        if (Test-Path "C:\ffmpeg\ffmpeg.exe") {
            $ffmpegPath = "C:\ffmpeg\ffmpeg.exe"
            # Add to system PATH
            $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            if ($machinePath -notmatch "C:\\ffmpeg") {
                [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;C:\ffmpeg", "Machine")
                $env:Path = "$env:Path;C:\ffmpeg"
            }
            WOK "FFmpeg copied to C:\ffmpeg and added to system PATH"
        } else {
            WWRN "Could not copy FFmpeg"
        }
    } else {
        # Ensure FFmpeg dir is in system PATH (so Premiere can find it)
        $ffDir = Split-Path $ffmpegPath
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $allPath = "$machinePath;$userPath"
        if ($allPath -notmatch [regex]::Escape($ffDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$ffDir", "Machine")
            $env:Path = "$env:Path;$ffDir"
            WOK "FFmpeg: $ffmpegPath (added dir to system PATH)"
        } else {
            WOK "FFmpeg: $ffmpegPath"
        }
    }
    $ffmpegOK = $true
} else {
    # Try installing via winget
    try {
        $null = Get-Command winget -ErrorAction Stop
        WINF "Installing FFmpeg via winget..."
        $wingetOut = cmd /c "winget install Gyan.FFmpeg --accept-package-agreements --accept-source-agreements --silent"
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        try {
            $null = Get-Command ffmpeg -ErrorAction Stop
            WOK "FFmpeg installed via winget"
            $ffmpegOK = $true
        } catch {
            WWRN "FFmpeg installed but not in PATH yet. Will work after Premiere restart."
        }
    } catch {
        WWRN "FFmpeg not found. Install from: https://www.gyan.dev/ffmpeg/builds/"
        WWRN "Download, extract to C:\ffmpeg, and add to PATH"
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 4: CEP Debug Mode
# ═══════════════════════════════════════════════════════════
WHDR 4 $TOTAL_STEPS "CEP Debug Mode"

foreach ($v in @("9","10","11","12")) {
    $regPath = "HKCU:\Software\Adobe\CSXS.$v"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    New-ItemProperty -Path $regPath -Name "PlayerDebugMode" -Value "1" -PropertyType String -Force | Out-Null
}
WOK "CEP debug mode enabled (CSXS 9-12)"

# ═══════════════════════════════════════════════════════════
#  STEP 5: Download Plugin
# ═══════════════════════════════════════════════════════════
WHDR 5 $TOTAL_STEPS "Download plugin v$PLUGIN_VERSION"

$pluginZip = "$TEMP_DIR\haleem-ultra.zip"
$needDownload = $true

# Check if plugin already exists and is complete
if (Test-Path (Join-Path $PLUGIN_DIR "index.html")) {
    $existingFiles = (Get-ChildItem $PLUGIN_DIR -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($existingFiles -gt 300) {
        WOK "Plugin already installed ($existingFiles files). Skipping download."
        $needDownload = $false
    } else {
        WWRN "Plugin exists but incomplete ($existingFiles files). Re-downloading."
    }
}

if ($needDownload) {
    WINF "Downloading v$PLUGIN_VERSION from GitHub..."
    WINF "URL: $PLUGIN_ZIP_URL"
    
    $dlOK = Safe-Download $PLUGIN_ZIP_URL $pluginZip 1000000
    if (-not $dlOK) {
        WERR "Plugin download failed after all methods!"
        WERR "Try downloading manually:"
        WERR "  $PLUGIN_ZIP_URL"
        WERR "Then extract to:"
        WERR "  $PLUGIN_DIR"
        return
    }
    
    $zipSize = [math]::Round((Get-Item $pluginZip).Length / 1MB, 1)
    WOK "Downloaded ($zipSize MB)"
}

# ═══════════════════════════════════════════════════════════
#  STEP 6: Extract Plugin (Unicode-safe)
# ═══════════════════════════════════════════════════════════
WHDR 6 $TOTAL_STEPS "Extract plugin"

if ($needDownload) {
    # Ensure target dirs exist
    if (-not (Test-Path $EXT_DIR)) { New-Item -ItemType Directory -Path $EXT_DIR -Force | Out-Null }
    if (-not (Test-Path $PLUGIN_DIR)) { New-Item -ItemType Directory -Path $PLUGIN_DIR -Force | Out-Null }
    
    if ($_hasUnicode) {
        # Unicode path: extract to safe temp first, then robocopy
        $extractTemp = "$TEMP_DIR\plugin-extract"
        if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null
        
        WINF "Extracting to safe temp path..."
        $exOK = Safe-Extract $pluginZip $extractTemp
        
        if ($exOK) {
            # Check for nested folder
            $items = Get-ChildItem $extractTemp
            $sourceDir = $extractTemp
            if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
                $sourceDir = $items[0].FullName
            }
            
            # Use robocopy for Unicode-safe copy
            WINF "Copying to plugin directory..."
            $robocopyOut = cmd /c "robocopy `"$sourceDir`" `"$PLUGIN_DIR`" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS /NP"
            
            if (Test-Path (Join-Path $PLUGIN_DIR "index.html")) {
                $fileCount = (Get-ChildItem $PLUGIN_DIR -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                WOK "Plugin extracted ($fileCount files)"
            } else {
                WWRN "robocopy may have issues. Trying direct extract..."
                $exOK2 = Safe-Extract $pluginZip $PLUGIN_DIR
                if ($exOK2 -and (Test-Path (Join-Path $PLUGIN_DIR "index.html"))) {
                    WOK "Plugin extracted (fallback)"
                } else {
                    WERR "Plugin extraction failed!"
                    return
                }
            }
        } else {
            WERR "All extraction methods failed!"
            return
        }
    } else {
        # ASCII path: extract directly
        WINF "Extracting..."
        $exOK = Safe-Extract $pluginZip $PLUGIN_DIR
        
        if ($exOK) {
            # Check for nested folder issue
            $nestedDir = Join-Path $PLUGIN_DIR "com.haleem.ultra.client"
            if ((Test-Path $nestedDir) -and (Test-Path (Join-Path $nestedDir "index.html"))) {
                WINF "Fixing nested folder structure..."
                Get-ChildItem $nestedDir | ForEach-Object { Move-Item $_.FullName $PLUGIN_DIR -Force -ErrorAction SilentlyContinue }
                Remove-Item $nestedDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            if (Test-Path (Join-Path $PLUGIN_DIR "index.html")) {
                $fileCount = (Get-ChildItem $PLUGIN_DIR -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                WOK "Plugin extracted ($fileCount files)"
            } else {
                WERR "Extraction succeeded but index.html not found!"
                return
            }
        } else {
            WERR "All extraction methods failed!"
            return
        }
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 7: broll-server npm install
# ═══════════════════════════════════════════════════════════
WHDR 7 $TOTAL_STEPS "broll-server dependencies"

$brollDir = Join-Path $PLUGIN_DIR "broll-server"
$brollPkg = Join-Path $brollDir "package.json"
$brollMod = Join-Path $brollDir "node_modules"

if (Test-Path $brollMod) {
    WOK "node_modules already exists"
} elseif (Test-Path $brollPkg) {
    $npmCmd = "C:\Program Files\nodejs\npm.cmd"
    if (-not (Test-Path $npmCmd)) {
        try { $npmCmd = (Get-Command npm -ErrorAction Stop).Source } catch { $npmCmd = "npm" }
    }
    
    WINF "Running npm install..."
    Push-Location $brollDir
    $npmOut = cmd /c "`"$npmCmd`" install --omit=dev"
    Pop-Location
    
    if (Test-Path $brollMod) { WOK "node_modules installed" }
    else { WWRN "npm install may have failed. broll features may not work." }
} else {
    WWRN "broll-server/package.json not found"
}

# ═══════════════════════════════════════════════════════════
#  STEP 8: Python .venv
# ═══════════════════════════════════════════════════════════
WHDR 8 $TOTAL_STEPS "Python virtual environment"

$venvOK = $false

# Check if existing .venv works
if (Test-Path $VENV_PY) {
    $venvTest = Safe-Run $VENV_PY @("-c", "import sys; print(sys.prefix)")
    if ($venvTest.ExitCode -eq 0) {
        WOK ".venv exists and works"
        $venvOK = $true
    } else {
        WWRN ".venv exists but broken. Recreating..."
    }
}

if (-not $venvOK) {
    # Remove old broken venv
    if (Test-Path $VENV_DIR) {
        $venvItem = Get-Item $VENV_DIR -Force -ErrorAction SilentlyContinue
        if ($venvItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $rmdirOut = cmd /c "rmdir `"$VENV_DIR`""
        } else {
            Remove-Item $VENV_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if ($SAFE_VENV) {
        # Unicode path: create venv at safe location + junction
        WINF "Creating .venv at safe path: $SAFE_VENV"
        
        if (Test-Path $SAFE_VENV) { Remove-Item $SAFE_VENV -Recurse -Force -ErrorAction SilentlyContinue }
        
        $venvResult = Safe-Run $PYTHON_EXE @("-m", "venv", $SAFE_VENV)
        
        if (Test-Path "$SAFE_VENV\Scripts\python.exe") {
            WOK ".venv created at $SAFE_VENV"
            
            WINF "Creating junction: .venv -> $SAFE_VENV"
            $mkOut = cmd /c "mklink /J `"$VENV_DIR`" `"$SAFE_VENV`""
            
            if (Test-Path $VENV_PY) {
                WOK "Junction created successfully"
                $venvOK = $true
            } else {
                # Junction failed, try direct
                WWRN "Junction failed, trying direct creation..."
                $venvResult2 = Safe-Run $PYTHON_EXE @("-m", "venv", $VENV_DIR)
                if (Test-Path $VENV_PY) {
                    WOK ".venv created directly"
                    $venvOK = $true
                }
            }
        } else {
            # Safe path also failed, try direct
            WWRN "Safe path failed, trying direct..."
            $venvResult3 = Safe-Run $PYTHON_EXE @("-m", "venv", $VENV_DIR)
            if (Test-Path $VENV_PY) {
                WOK ".venv created directly"
                $venvOK = $true
            }
        }
    } else {
        # ASCII path: create directly
        WINF "Creating .venv..."
        $venvResult = Safe-Run $PYTHON_EXE @("-m", "venv", $VENV_DIR)
        if (Test-Path $VENV_PY) {
            WOK ".venv created"
            $venvOK = $true
        } else {
            # Try with --clear
            WWRN "Retrying with --clear..."
            $venvResult2 = Safe-Run $PYTHON_EXE @("-m", "venv", "--clear", $VENV_DIR)
            if (Test-Path $VENV_PY) {
                WOK ".venv created (with --clear)"
                $venvOK = $true
            }
        }
    }
    
    if (-not $venvOK) {
        WERR ".venv creation failed after all attempts!"
        WERR "Try manually: $PYTHON_EXE -m venv $VENV_DIR"
        return
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 9: Python Packages
# ═══════════════════════════════════════════════════════════
WHDR 9 $TOTAL_STEPS "Python packages (this may take several minutes)"

# Upgrade pip
WINF "Upgrading pip..."
$pipUp = Safe-Run $PIP_EXE @("install", "--isolated", "--upgrade", "pip")

# Check PyTorch
$torchOK = $false
$torchTest = Safe-Run $VENV_PY @("-c", "import torch; print(torch.__version__)")
if ($torchTest.ExitCode -eq 0 -and $torchTest.Output -match "2\.5\.1") {
    WOK "PyTorch already installed: $($torchTest.Output.Trim())"
    $torchOK = $true
}

if (-not $torchOK) {
    WINF "Installing PyTorch (CUDA 12.1) — downloading ~2.5 GB..."
    
    # Uninstall old/corrupted torch
    $uninstall = Safe-Run $PIP_EXE @("uninstall", "torch", "torchaudio", "-y")
    
    # Install torch
    $torchInstallArgs = @("install", "--isolated", "torch==2.5.1+cu121", "torchaudio==2.5.1+cu121", "--extra-index-url", $TORCH_INDEX)
    $torchResult = Safe-Run $PIP_EXE $torchInstallArgs
    
    # Verify
    $torchTest2 = Safe-Run $VENV_PY @("-c", "import torch; print(torch.__version__)")
    if ($torchTest2.ExitCode -eq 0) {
        WOK "PyTorch installed: $($torchTest2.Output.Trim())"
    } else {
        WWRN "PyTorch may have issues: $($torchTest2.Error)"
    }
}

# Install remaining packages
WINF "Installing remaining packages..."
$pipInstallArgs = @("install", "--isolated") + $PIP_PKGS
$pipResult = Safe-Run $PIP_EXE $pipInstallArgs

# Install from requirements.txt if exists
$reqFile = Join-Path $PLUGIN_DIR "requirements.txt"
if (Test-Path $reqFile) {
    WINF "Installing from requirements.txt..."
    $reqResult = Safe-Run $PIP_EXE @("install", "--isolated", "-r", $reqFile)
}

WOK "Package installation complete"

# ═══════════════════════════════════════════════════════════
#  STEP 10: Silero VAD Model Fix
# ═══════════════════════════════════════════════════════════
WHDR 10 $TOTAL_STEPS "Silero VAD model"

$sileroModel = Join-Path $PLUGIN_DIR "ai_models\silero_vad.onnx"
$sileroCacheDir = Join-Path $env:USERPROFILE ".cache\torch\hub\snakers4_silero-vad_master\src\silero_vad\data"

if (Test-Path $sileroModel) {
    WOK "Silero model exists in plugin"
    
    # Copy to torch cache (for code that looks there)
    $sileroCacheFile = Join-Path $sileroCacheDir "silero_vad.onnx"
    if (-not (Test-Path $sileroCacheFile)) {
        WINF "Copying model to torch cache..."
        if (-not (Test-Path $sileroCacheDir)) { New-Item -ItemType Directory -Path $sileroCacheDir -Force | Out-Null }
        Copy-Item $sileroModel $sileroCacheFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $sileroCacheFile) { WOK "Model copied to cache" }
    } else {
        WOK "Model also in torch cache"
    }
    
    # Patch silero_detector.py to check ai_models/ first
    $detPy = Join-Path $PLUGIN_DIR "speech_detection\silero_detector.py"
    if (Test-Path $detPy) {
        $detContent = [System.IO.File]::ReadAllText($detPy, [System.Text.Encoding]::UTF8)
        if ($detContent -match "_SILERO_LOCAL" -or $detContent -match "_ONNX_MODEL_LOCAL" -or $detContent -match "_BUNDLED_MODEL") {
            WOK "silero_detector.py already patched"
        } elseif ($detContent -match '_ONNX_MODEL\s*=\s*os\.path\.join\(_SILERO_CACHE') {
            WINF "Patching silero_detector.py to use local model first..."
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
            WOK "silero_detector.py patched"
        }
    }
} else {
    WWRN "Silero model not found in ai_models/"
}

# ═══════════════════════════════════════════════════════════
#  STEP 11: Film Impact (optional)
# ═══════════════════════════════════════════════════════════
WHDR 11 $TOTAL_STEPS "Film Impact Premium Video Effects"

$fiInstalled = Test-Path "C:\Program Files\Common Files\Adobe\CEP\extensions\Film Impact Dashboard"
if ($fiInstalled) {
    WOK "Film Impact already installed"
} else {
    $fiUrl = $null
    try {
        $latestRel = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" -UseBasicParsing
        $fiAsset = $latestRel.assets | Where-Object { $_.name -match 'Film.*Impact.*\.exe$' } | Select-Object -First 1
        if ($fiAsset) { $fiUrl = $fiAsset.browser_download_url }
    } catch {}
    
    if ($fiUrl) {
        $fiInstaller = "$TEMP_DIR\FilmImpact-Setup.exe"
        WINF "Downloading Film Impact..."
        $dlOK = Safe-Download $fiUrl $fiInstaller 1000000
        if ($dlOK) {
            WINF "Installing Film Impact..."
            Start-Process -FilePath $fiInstaller -ArgumentList "/VERYSILENT", "/NORESTART" -Wait -NoNewWindow
            if (Test-Path "C:\Program Files\Common Files\Adobe\CEP\extensions\Film Impact Dashboard") {
                WOK "Film Impact installed"
            } else {
                WWRN "Film Impact may need manual installation"
            }
        }
    } else {
        WINF "Film Impact not found in release assets. Skipping."
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 12: COMPREHENSIVE VERIFICATION
# ═══════════════════════════════════════════════════════════
WHDR 12 $TOTAL_STEPS "Comprehensive Verification"

Write-Host ""
Write-Host "  --- Plugin Files ---" -ForegroundColor White
$allOK = $true
$failCount = 0

$fileChecks = @(
    @{ N = "index.html";                  P = (Join-Path $PLUGIN_DIR "index.html") },
    @{ N = "CSXS/manifest.xml";           P = (Join-Path $PLUGIN_DIR "CSXS\manifest.xml") },
    @{ N = "host/premiere.jsx";           P = (Join-Path $PLUGIN_DIR "host\premiere.jsx") },
    @{ N = "backend_server.pyc";          P = (Join-Path $PLUGIN_DIR "scripts\backend_server.pyc") },
    @{ N = "process_video.pyc";           P = (Join-Path $PLUGIN_DIR "scripts\process_video.pyc") },
    @{ N = "version.json";                P = (Join-Path $PLUGIN_DIR "version.json") },
    @{ N = "activation-gate.js";          P = (Join-Path $PLUGIN_DIR "activation-gate.js") },
    @{ N = "requirements.txt";            P = (Join-Path $PLUGIN_DIR "requirements.txt") },
    @{ N = "template-engine.js";          P = (Join-Path $PLUGIN_DIR "template-engine.js") },
    @{ N = "icon.png";                    P = (Join-Path $PLUGIN_DIR "icon.png") },
    @{ N = "ai_models/silero_vad.onnx";   P = (Join-Path $PLUGIN_DIR "ai_models\silero_vad.onnx") },
    @{ N = "broll-server/server.js";      P = (Join-Path $PLUGIN_DIR "broll-server\server.js") },
    @{ N = "broll-server/node_modules";   P = (Join-Path $PLUGIN_DIR "broll-server\node_modules") }
)

foreach ($c in $fileChecks) {
    if (Test-Path $c.P) { WOK $c.N }
    else { WERR "$($c.N) — MISSING"; $allOK = $false; $failCount++ }
}

Write-Host ""
Write-Host "  --- Directories ---" -ForegroundColor White
$dirChecks = @(
    "activation-server", "ai_models", "audio_engine", "broll-server",
    "core", "CSXS", "host", "jsx", "lib", "panel", "scripts",
    "silence_detection", "speech_detection", "vendor", "video_engine",
    "waveform_analysis"
)
foreach ($d in $dirChecks) {
    $dp = Join-Path $PLUGIN_DIR $d
    if (Test-Path $dp) { WOK $d }
    else { WERR "$d — MISSING DIRECTORY"; $allOK = $false; $failCount++ }
}

Write-Host ""
Write-Host "  --- Runtime ---" -ForegroundColor White

# Python
if (Test-Path $PYTHON_EXE) { WOK "Python: $PYTHON_EXE" }
else { WERR "Python not found!"; $allOK = $false; $failCount++ }

# .venv
if (Test-Path $VENV_PY) { WOK ".venv: $VENV_DIR" }
else { WERR ".venv missing!"; $allOK = $false; $failCount++ }

# Node.js
if (Test-Path $NODE_EXE) { WOK "Node.js: $NODE_EXE" }
else { WWRN "Node.js not found (broll features may not work)" }

# FFmpeg
try {
    $null = Get-Command ffmpeg -ErrorAction Stop
    WOK "FFmpeg in PATH"
} catch {
    if (Test-Path "C:\ffmpeg\ffmpeg.exe") { WOK "FFmpeg at C:\ffmpeg" }
    else { WWRN "FFmpeg not in PATH (pipeline may fail)"; $failCount++ }
}

# CEP Debug Mode
$cepOK = $true
foreach ($v in @("9","10","11","12")) {
    $val = (Get-ItemProperty -Path "HKCU:\Software\Adobe\CSXS.$v" -Name "PlayerDebugMode" -ErrorAction SilentlyContinue).PlayerDebugMode
    if ($val -ne "1") { $cepOK = $false }
}
if ($cepOK) { WOK "CEP Debug Mode enabled" }
else { WERR "CEP Debug Mode not fully enabled"; $allOK = $false; $failCount++ }

Write-Host ""
Write-Host "  --- Python Package Imports ---" -ForegroundColor White

# Test critical imports
$importTests = @(
    @{ N = "torch";        C = "import torch; print(torch.__version__)" },
    @{ N = "torchaudio";   C = "import torchaudio; print(torchaudio.__version__)" },
    @{ N = "numpy";        C = "import numpy; print(numpy.__version__)" },
    @{ N = "scipy";        C = "import scipy; print(scipy.__version__)" },
    @{ N = "librosa";      C = "import librosa; print(librosa.__version__)" },
    @{ N = "soundfile";    C = "import soundfile; print(soundfile.__version__)" },
    @{ N = "whisper";      C = "import whisper; print(whisper.__version__)" },
    @{ N = "onnxruntime";  C = "import onnxruntime; print(onnxruntime.__version__)" },
    @{ N = "pydantic";     C = "import pydantic; print(pydantic.__version__)" }
)

foreach ($t in $importTests) {
    $result = Safe-Run $VENV_PY @("-c", $t.C)
    if ($result.ExitCode -eq 0) {
        WOK "$($t.N) $($result.Output.Trim())"
    } else {
        WERR "$($t.N) — IMPORT FAILED"
        $allOK = $false
        $failCount++
    }
}

# ═══════════════════════════════════════════════════════════
#  Cleanup
# ═══════════════════════════════════════════════════════════
Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

# ═══════════════════════════════════════════════════════════
#  Final Result
# ═══════════════════════════════════════════════════════════
Write-Host ""
if ($allOK -and $failCount -eq 0) {
    Write-Host "  +=============================================+" -ForegroundColor Green
    Write-Host "  |  [OK] HALEEM-ULTRA installed successfully!  |" -ForegroundColor Green
    Write-Host "  |  [OK] All $($fileChecks.Count + $dirChecks.Count + $importTests.Count) checks passed                    |" -ForegroundColor Green
    Write-Host "  |                                             |" -ForegroundColor Green
    Write-Host "  |  1. Restart Premiere Pro                    |" -ForegroundColor Green
    Write-Host "  |  2. Window > Extensions > HALEEM-ULTRA      |" -ForegroundColor Green
    Write-Host "  +=============================================+" -ForegroundColor Green
} elseif ($failCount -le 3) {
    Write-Host "  +=============================================+" -ForegroundColor Yellow
    Write-Host "  |  [!!] Installed with $failCount warning(s)           |" -ForegroundColor Yellow
    Write-Host "  |                                             |" -ForegroundColor Yellow
    Write-Host "  |  Most features should work.                 |" -ForegroundColor Yellow
    Write-Host "  |  Review warnings above.                     |" -ForegroundColor Yellow
    Write-Host "  |                                             |" -ForegroundColor Yellow
    Write-Host "  |  1. Restart Premiere Pro                    |" -ForegroundColor Yellow
    Write-Host "  |  2. Window > Extensions > HALEEM-ULTRA      |" -ForegroundColor Yellow
    Write-Host "  +=============================================+" -ForegroundColor Yellow
} else {
    Write-Host "  +=============================================+" -ForegroundColor Red
    Write-Host "  |  [XX] Installation has $failCount issue(s)           |" -ForegroundColor Red
    Write-Host "  |                                             |" -ForegroundColor Red
    Write-Host "  |  Check the errors above.                    |" -ForegroundColor Red
    Write-Host "  |  Contact support with a screenshot.         |" -ForegroundColor Red
    Write-Host "  +=============================================+" -ForegroundColor Red
}
Write-Host ""
