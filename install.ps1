<#
.SYNOPSIS
    HALEEM-ULTRA — Bulletproof Installer v3.1
.DESCRIPTION
    Installs HALEEM-ULTRA plugin with ALL dependencies.
    Works on ALL machines including Arabic/Unicode usernames.
    Smart: skips what already works, repairs only what's broken.
    
    Run as Administrator in PowerShell:
    Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/haleemrz/HALEEM-ULTRA-TestReleases/master/install.ps1 | iex
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

# ─── Progress bar ─────────────────────────────────────────
function Show-Bar {
    param([int]$Pct, [string]$Label)
    $w = 30
    $filled = [math]::Floor($w * $Pct / 100)
    $empty = $w - $filled
    $bar = ("[" + ("=" * $filled) + ("." * $empty) + "]")
    Write-Host "`r  $bar $Pct% $Label    " -NoNewline -ForegroundColor Cyan
}

# ─── Quick test: run exe and get output (for --version, -c) ──
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

# ─── Download with progress (4 methods) ──────────────────
function Safe-Download {
    param([string]$Url, [string]$OutFile, [int]$MinSize = 1000)
    
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
    
    # Method 1: WebClient with progress events
    try {
        WINF "Method 1: WebClient..."
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "HALEEM-ULTRA-Installer/3.1")
        
        $lastPct = -1
        $dlDone = $false
        Register-ObjectEvent $wc DownloadProgressChanged -Action {
            $p = $EventArgs.ProgressPercentage
            if ($p -ne $script:lastPct -and ($p % 5 -eq 0)) {
                $script:lastPct = $p
                $mb = [math]::Round($EventArgs.BytesReceived / 1MB, 1)
                Show-Bar $p "${mb}MB"
            }
        } | Out-Null
        Register-ObjectEvent $wc DownloadFileCompleted -Action { $script:dlDone = $true } | Out-Null
        
        $wc.DownloadFileAsync([Uri]$Url, $OutFile)
        
        $timeout = 600
        $elapsed = 0
        while (-not $dlDone -and $elapsed -lt $timeout) {
            Start-Sleep -Milliseconds 500
            $elapsed += 0.5
        }
        Write-Host ""
        
        Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue
        
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
        $wc.Dispose()
    } catch {
        Write-Host ""
        WINF "WebClient failed: $($_.Exception.Message)"
        Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue
    }
    
    # Method 2: curl.exe (shows own progress)
    try {
        $curlExe = "C:\Windows\System32\curl.exe"
        if (Test-Path $curlExe) {
            WINF "Method 2: curl.exe..."
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
            cmd /c "`"$curlExe`" -L -o `"$OutFile`" -# `"$Url`""
            if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
        }
    } catch { WINF "curl.exe failed" }
    
    # Method 3: Invoke-WebRequest
    try {
        WINF "Method 3: Invoke-WebRequest..."
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "Invoke-WebRequest failed" }
    
    # Method 4: BitsTransfer
    try {
        WINF "Method 4: BitsTransfer..."
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $Url -Destination $OutFile -Description "HALEEM-ULTRA"
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt $MinSize) { return $true }
    } catch { WINF "BitsTransfer failed" }
    
    return $false
}

# ─── Extract (4 methods) ─────────────────────────────────
function Safe-Extract {
    param([string]$ZipFile, [string]$DestDir)
    
    try {
        Expand-Archive -Path $ZipFile -DestinationPath $DestDir -Force; return $true
    } catch { WINF "Expand-Archive failed, trying .NET..." }
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
        $total = $archive.Entries.Count
        $i = 0
        foreach ($entry in $archive.Entries) {
            $i++
            if ($i % 50 -eq 0) { Show-Bar ([math]::Floor($i * 100 / $total)) "$i/$total files" }
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
        Write-Host ""
        return $true
    } catch { Write-Host ""; WINF ".NET ZipFile failed, trying COM..." }
    
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

# ─── Run pip with live output ─────────────────────────────
function Run-Pip {
    param([string]$PipExe, [string[]]$PipArgs, [string]$Label)
    WINF "$Label"
    $allArgs = $PipArgs -join " "
    cmd /c "`"$PipExe`" $allArgs"
    return $LASTEXITCODE -eq 0
}

# ═══════════════════════════════════════════════════════════
#  STEP 0: Pre-flight
# ═══════════════════════════════════════════════════════════
$TOTAL = 12

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    WERR "Run as Administrator! Right-click PowerShell -> Run as Administrator"
    return
}

$_hasUnicode = $env:USERPROFILE -match '[^\x00-\x7F]'

Write-Host ""
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host "  |  HALEEM-ULTRA  Installer v3.1 (Bulletproof) |" -ForegroundColor Magenta
Write-Host "  +=============================================+" -ForegroundColor Magenta
Write-Host ""
Write-Host "  User:    $env:USERNAME" -ForegroundColor Gray
Write-Host "  Profile: $env:USERPROFILE" -ForegroundColor Gray
Write-Host "  OS:      $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "  PS:      $($PSVersionTable.PSVersion)" -ForegroundColor Gray
if ($_hasUnicode) { WWRN "Unicode username detected - using safe paths" }

# ═══════════════════════════════════════════════════════════
#  Configuration
# ═══════════════════════════════════════════════════════════
$REPO_OWNER = "haleemrz"
$REPO_NAME  = "HALEEM-ULTRA-Releases"
$PY_VER     = "3.11.9"
$NODE_VER   = "25.2.1"

if ($_hasUnicode) {
    $PY_DIR   = "C:\Python311"
    $SAFE_VENV = "C:\haleem-venv"
    $TEMP_DIR  = "C:\haleem-temp"
} else {
    $PY_DIR   = "$env:LOCALAPPDATA\Programs\Python\Python311"
    $SAFE_VENV = ""
    $TEMP_DIR  = "$env:TEMP\haleem-ultra-install"
}

$PY_EXE    = "$PY_DIR\python.exe"
$EXT_DIR   = Join-Path $env:APPDATA "Adobe\CEP\extensions"
$PLUG_DIR  = Join-Path $EXT_DIR "com.haleem.ultra.client"
$VENV_DIR  = Join-Path $EXT_DIR ".venv"
$PIP_EXE   = Join-Path $VENV_DIR "Scripts\pip.exe"
$VENV_PY   = Join-Path $VENV_DIR "Scripts\python.exe"
$NODE_EXE  = "C:\Program Files\nodejs\node.exe"

$TORCH_IDX = "https://download.pytorch.org/whl/cu121"
$PIP_PKGS  = @(
    "numpy==2.4.5","scipy==1.17.1","soundfile==0.13.1",
    "librosa==0.11.0","tqdm==4.67.3","pydantic==2.13.4",
    "onnxruntime==1.26.0","openai-whisper==20250625"
)

# Detect latest release
$PLUG_VER = "2.8"
$PLUG_URL = ""
try {
    $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases?per_page=10" -UseBasicParsing
    foreach ($r in $rels) {
        $za = $r.assets | Where-Object { $_.name -match '^haleem-ultra-v.*\.zip$' } | Select-Object -First 1
        if ($za) { $PLUG_VER = $r.tag_name -replace '^v',''; $PLUG_URL = $za.browser_download_url; break }
    }
} catch { WINF "GitHub API unreachable, using fallback URL" }
if (-not $PLUG_URL) { $PLUG_URL = "https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/v${PLUG_VER}/haleem-ultra-v${PLUG_VER}.zip" }

if (Test-Path $TEMP_DIR) { Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

# ═══════════════════════════════════════════════════════════
#  STEP 1: Python 3.11
# ═══════════════════════════════════════════════════════════
WHDR 1 $TOTAL "Python $PY_VER"

$pyFound = $false

# Search existing Python
$pyCandidates = @(
    $PY_EXE,
    "C:\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "C:\Program Files\Python311\python.exe"
)
foreach ($pc in $pyCandidates) {
    if (Test-Path $pc) {
        $t = Quick-Test $pc @("--version")
        if ($t.OK -and $t.Out -match "3\.11") {
            $PY_EXE = $pc; $PY_DIR = Split-Path $pc
            WOK "Python OK: $($t.Out) at $PY_DIR"
            $pyFound = $true
            break
        } else {
            $tMsg = "$($t.Out) $($t.Err)"
            WWRN "Found $pc but broken: $tMsg"
        }
    }
}

if (-not $pyFound) {
    $pyUrl = "https://www.python.org/ftp/python/$PY_VER/python-$PY_VER-amd64.exe"
    $pyInst = "$TEMP_DIR\python-installer.exe"
    
    WINF "Downloading Python $PY_VER..."
    $dlOK = Safe-Download $pyUrl $pyInst 20000000
    if (-not $dlOK) { WERR "Python download failed!"; return }
    
    # Install silently with Start-Process (NOT Safe-Run)
    WINF "Installing Python to $PY_DIR (silent)..."
    Start-Process -FilePath $pyInst -ArgumentList "/quiet","InstallAllUsers=1","PrependPath=0","Include_pip=1","Include_test=0","TargetDir=$PY_DIR" -Wait -NoNewWindow
    
    # Wait a moment for files to settle
    $waited = 0
    while (-not (Test-Path $PY_EXE) -and $waited -lt 30) {
        Start-Sleep -Seconds 1; $waited++
        Show-Bar ([math]::Min(95, $waited * 3)) "Installing..."
    }
    Write-Host ""
    
    if (Test-Path $PY_EXE) {
        $t = Quick-Test $PY_EXE @("--version")
        WOK "Python installed: $($t.Out)"
    } else {
        # Attempt 2
        WWRN "Attempt 1 failed. Trying all-users default..."
        Start-Process -FilePath $pyInst -ArgumentList "/quiet","InstallAllUsers=1","PrependPath=0","Include_pip=1" -Wait -NoNewWindow
        Start-Sleep -Seconds 5
        
        foreach ($alt in @("C:\Program Files\Python311\python.exe","C:\Python311\python.exe")) {
            if (Test-Path $alt) { $PY_EXE = $alt; $PY_DIR = Split-Path $alt; break }
        }
        
        if (Test-Path $PY_EXE) {
            WOK "Python installed: $PY_DIR"
        } else {
            WERR "Python install failed! Install manually from python.org to C:\Python311"
            return
        }
    }
}

# Final verify
$pyOK = Quick-Test $PY_EXE @("-c","print('OK')")
if (-not $pyOK.OK) { WERR "Python not functional!"; return }

# ═══════════════════════════════════════════════════════════
#  STEP 2: Node.js
# ═══════════════════════════════════════════════════════════
WHDR 2 $TOTAL "Node.js"

$nodeOK = $false
if (Test-Path $NODE_EXE) {
    $nv = Quick-Test $NODE_EXE @("--version")
    if ($nv.OK) { WOK "Node.js OK: $($nv.Out)"; $nodeOK = $true }
    else { WWRN "Node.js exists but broken" }
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
        WINF "Installing Node.js (silent)..."
        Start-Process msiexec.exe -ArgumentList "/i","`"$nodeInst`"","/quiet","/norestart" -Wait -NoNewWindow
        Start-Sleep -Seconds 3
        if (Test-Path "C:\Program Files\nodejs\node.exe") { $NODE_EXE = "C:\Program Files\nodejs\node.exe"; WOK "Node.js installed" }
        else { WWRN "Node.js install may need restart" }
    } else { WWRN "Node.js download failed" }
}

# ═══════════════════════════════════════════════════════════
#  STEP 3: FFmpeg
# ═══════════════════════════════════════════════════════════
WHDR 3 $TOTAL "FFmpeg"

$ffOK = $false
$ffPath = $null

# Find ffmpeg
try { $ffc = Get-Command ffmpeg -ErrorAction Stop; $ffPath = $ffc.Source } catch {}
if (-not $ffPath) {
    foreach ($fc in @("C:\ffmpeg\ffmpeg.exe","C:\ffmpeg\bin\ffmpeg.exe","$env:APPDATA\HappyDuckAI\ffmpeg\ffmpeg.exe","C:\ProgramData\chocolatey\bin\ffmpeg.exe")) {
        if (Test-Path $fc) { $ffPath = $fc; break }
    }
}

if ($ffPath) {
    # Verify it works
    $ffTest = Quick-Test $ffPath @("-version")
    if ($ffTest.OK) {
        # Check if in Unicode path - copy to safe location
        if ("$ffPath" -match '[^\x00-\x7F]') {
            WWRN "FFmpeg in Unicode path: $ffPath"
            $ffSrc = Split-Path $ffPath
            if (-not (Test-Path "C:\ffmpeg")) { New-Item -ItemType Directory -Path "C:\ffmpeg" -Force | Out-Null }
            Copy-Item (Join-Path $ffSrc "ffmpeg.exe") "C:\ffmpeg\ffmpeg.exe" -Force -ErrorAction SilentlyContinue
            if (Test-Path (Join-Path $ffSrc "ffprobe.exe")) { Copy-Item (Join-Path $ffSrc "ffprobe.exe") "C:\ffmpeg\ffprobe.exe" -Force -ErrorAction SilentlyContinue }
            $ffPath = "C:\ffmpeg\ffmpeg.exe"
        }
        
        # Ensure in system PATH
        $ffDir = Split-Path $ffPath
        $mp = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        if ($mp -notmatch [regex]::Escape($ffDir)) {
            $newPath = "$mp;$ffDir"
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            $env:Path = "$env:Path;$ffDir"
        }
        WOK "FFmpeg OK: $ffPath"
        $ffOK = $true
    } else {
        WWRN "FFmpeg exists but broken. Removing..."
        Remove-Item $ffPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not $ffOK) {
    try {
        $null = Get-Command winget -ErrorAction Stop
        WINF "Installing FFmpeg via winget..."
        cmd /c "winget install Gyan.FFmpeg --accept-package-agreements --accept-source-agreements --silent"
        $mPath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        $uPath = [System.Environment]::GetEnvironmentVariable("Path","User")
        $env:Path = "$mPath;$uPath"
        try { $null = Get-Command ffmpeg -ErrorAction Stop; WOK "FFmpeg installed"; $ffOK = $true } catch { WWRN "FFmpeg installed - restart to use" }
    } catch { WWRN "Install FFmpeg manually: https://www.gyan.dev/ffmpeg/builds/" }
}

# ═══════════════════════════════════════════════════════════
#  STEP 4: CEP Debug Mode
# ═══════════════════════════════════════════════════════════
WHDR 4 $TOTAL "CEP Debug Mode"

$cepAlready = $true
foreach ($v in @("9","10","11","12")) {
    $rp = "HKCU:\Software\Adobe\CSXS.$v"
    $val = $null
    try { $val = (Get-ItemProperty -Path $rp -Name "PlayerDebugMode" -ErrorAction Stop).PlayerDebugMode } catch {}
    if ($val -ne "1") { $cepAlready = $false }
}

if ($cepAlready) {
    WSKP "CEP debug mode already enabled"
} else {
    foreach ($v in @("9","10","11","12")) {
        $rp = "HKCU:\Software\Adobe\CSXS.$v"
        if (-not (Test-Path $rp)) { New-Item -Path $rp -Force | Out-Null }
        New-ItemProperty -Path $rp -Name "PlayerDebugMode" -Value "1" -PropertyType String -Force | Out-Null
    }
    WOK "CEP debug mode enabled (CSXS 9-12)"
}

# ═══════════════════════════════════════════════════════════
#  STEP 5 & 6: Download & Extract Plugin
# ═══════════════════════════════════════════════════════════
WHDR 5 $TOTAL "Plugin v$PLUG_VER"

$pluginReady = $false
$pluginZip = "$TEMP_DIR\haleem-ultra.zip"

# Check existing installation
if (Test-Path (Join-Path $PLUG_DIR "index.html")) {
    $fc = (Get-ChildItem $PLUG_DIR -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    # Check critical files exist
    $criticals = @("index.html","CSXS\manifest.xml","host\premiere.jsx","scripts\backend_server.pyc","requirements.txt")
    $critOK = $true
    foreach ($cf in $criticals) {
        if (-not (Test-Path (Join-Path $PLUG_DIR $cf))) { $critOK = $false; break }
    }
    if ($critOK -and $fc -gt 300) {
        WSKP "Plugin already installed and complete - $fc files"
        $pluginReady = $true
    } else {
        WWRN "Plugin incomplete: $fc files, missing criticals. Re-downloading..."
        Remove-Item $PLUG_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $pluginReady) {
    WINF "Downloading v$PLUG_VER..."
    $dlOK = Safe-Download $PLUG_URL $pluginZip 1000000
    if (-not $dlOK) { WERR "Plugin download failed!"; return }
    $mb = [math]::Round((Get-Item $pluginZip).Length / 1MB, 1)
    WOK "Downloaded (${mb} MB)"
    
    WHDR 6 $TOTAL "Extracting plugin"
    if (-not (Test-Path $EXT_DIR)) { New-Item -ItemType Directory -Path $EXT_DIR -Force | Out-Null }
    if (-not (Test-Path $PLUG_DIR)) { New-Item -ItemType Directory -Path $PLUG_DIR -Force | Out-Null }
    
    if ($_hasUnicode) {
        $exTemp = "$TEMP_DIR\plugin-extract"
        New-Item -ItemType Directory -Path $exTemp -Force | Out-Null
        WINF "Extracting to safe temp..."
        $exOK = Safe-Extract $pluginZip $exTemp
        if ($exOK) {
            $items = Get-ChildItem $exTemp
            $src = $exTemp
            if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $src = $items[0].FullName }
            WINF "Copying to plugin directory..."
            cmd /c "robocopy `"$src`" `"$PLUG_DIR`" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS /NP" | Out-Null
        }
    } else {
        $exOK = Safe-Extract $pluginZip $PLUG_DIR
        # Fix nested folder
        $nested = Join-Path $PLUG_DIR "com.haleem.ultra.client"
        if ((Test-Path $nested) -and (Test-Path (Join-Path $nested "index.html"))) {
            Get-ChildItem $nested | ForEach-Object { Move-Item $_.FullName $PLUG_DIR -Force -ErrorAction SilentlyContinue }
            Remove-Item $nested -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if (Test-Path (Join-Path $PLUG_DIR "index.html")) {
        $fc = (Get-ChildItem $PLUG_DIR -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        WOK "Plugin extracted - $fc files"
        $pluginReady = $true
    } else {
        WERR "Extraction failed!"; return
    }
} else {
    WHDR 6 $TOTAL "Extract plugin"
    WSKP "Already extracted"
}

# ═══════════════════════════════════════════════════════════
#  STEP 7: broll-server
# ═══════════════════════════════════════════════════════════
WHDR 7 $TOTAL "broll-server"

$brollDir = Join-Path $PLUG_DIR "broll-server"
$brollMod = Join-Path $brollDir "node_modules"

if (Test-Path $brollMod) {
    # Verify it has content
    $modCount = (Get-ChildItem $brollMod -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($modCount -gt 5) {
        WSKP "node_modules OK - $modCount packages"
    } else {
        WWRN "node_modules broken - $modCount packages. Reinstalling..."
        Remove-Item $brollMod -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $brollMod) -and (Test-Path (Join-Path $brollDir "package.json"))) {
    $npmCmd = "C:\Program Files\nodejs\npm.cmd"
    if (-not (Test-Path $npmCmd)) { try { $npmCmd = (Get-Command npm -ErrorAction Stop).Source } catch { $npmCmd = "" } }
    if ($npmCmd) {
        WINF "npm install..."
        Push-Location $brollDir
        cmd /c "`"$npmCmd`" install --omit=dev"
        Pop-Location
        if (Test-Path $brollMod) { WOK "node_modules installed" }
        else { WWRN "npm install failed" }
    } else { WWRN "npm not found" }
} elseif (-not (Test-Path (Join-Path $brollDir "package.json"))) {
    WWRN "broll-server/package.json missing"
}

# ═══════════════════════════════════════════════════════════
#  STEP 8: Python .venv
# ═══════════════════════════════════════════════════════════
WHDR 8 $TOTAL "Python virtual environment"

$venvOK = $false

if (Test-Path $VENV_PY) {
    $vt = Quick-Test $VENV_PY @("-c","import sys; print(sys.prefix)")
    if ($vt.OK) {
        # Also verify pip works
        $pt = Quick-Test $PIP_EXE @("--version")
        if ($pt.OK) {
            WSKP ".venv OK"
            $venvOK = $true
        } else {
            WWRN ".venv exists but pip broken. Recreating..."
        }
    } else {
        WWRN ".venv exists but Python broken. Recreating..."
    }
}

if (-not $venvOK) {
    # Remove old
    if (Test-Path $VENV_DIR) {
        $vi = Get-Item $VENV_DIR -Force -ErrorAction SilentlyContinue
        if ($vi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$VENV_DIR`"" | Out-Null
        } else {
            Remove-Item $VENV_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if ($SAFE_VENV) {
        if (Test-Path $SAFE_VENV) { Remove-Item $SAFE_VENV -Recurse -Force -ErrorAction SilentlyContinue }
        WINF "Creating .venv at $SAFE_VENV..."
        Start-Process -FilePath $PY_EXE -ArgumentList "-m","venv",$SAFE_VENV -Wait -NoNewWindow
        
        if (Test-Path "$SAFE_VENV\Scripts\python.exe") {
            WINF "Creating junction..."
            cmd /c "mklink /J `"$VENV_DIR`" `"$SAFE_VENV`"" | Out-Null
            if (Test-Path $VENV_PY) { WOK ".venv created + junction"; $venvOK = $true }
        }
        
        if (-not $venvOK) {
            WWRN "Safe path failed, trying direct..."
            Start-Process -FilePath $PY_EXE -ArgumentList "-m","venv",$VENV_DIR -Wait -NoNewWindow
            if (Test-Path $VENV_PY) { WOK ".venv created directly"; $venvOK = $true }
        }
    } else {
        WINF "Creating .venv..."
        Start-Process -FilePath $PY_EXE -ArgumentList "-m","venv",$VENV_DIR -Wait -NoNewWindow
        if (Test-Path $VENV_PY) { WOK ".venv created"; $venvOK = $true }
        else {
            WWRN "Retrying with --clear..."
            Start-Process -FilePath $PY_EXE -ArgumentList "-m","venv","--clear",$VENV_DIR -Wait -NoNewWindow
            if (Test-Path $VENV_PY) { WOK ".venv created (--clear)"; $venvOK = $true }
        }
    }
    
    if (-not $venvOK) { WERR ".venv creation failed!"; return }
}

# ═══════════════════════════════════════════════════════════
#  STEP 9: Python Packages
# ═══════════════════════════════════════════════════════════
WHDR 9 $TOTAL "Python packages"

# Check what's already installed
$torchOK = $false
$pkgsOK  = $false

$tt = Quick-Test $VENV_PY @("-c","import torch; print(torch.__version__)")
if ($tt.OK -and $tt.Out -match "2\.5\.1") {
    WSKP "PyTorch OK: $($tt.Out)"
    $torchOK = $true
}

$pt = Quick-Test $VENV_PY @("-c","import numpy,scipy,librosa,soundfile,whisper,onnxruntime,pydantic; print('OK')")
if ($pt.OK -and $pt.Out -match "OK") {
    WSKP "All packages OK"
    $pkgsOK = $true
}

if (-not $torchOK -or -not $pkgsOK) {
    # Upgrade pip first
    Run-Pip $PIP_EXE @("install","--isolated","--upgrade","pip") "Upgrading pip..."
}

if (-not $torchOK) {
    WINF "Uninstalling old torch..."
    Run-Pip $PIP_EXE @("uninstall","torch","torchaudio","-y") "Cleaning old torch..."
    
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Yellow
    Write-Host "  |  Downloading PyTorch (~2.5 GB)             |" -ForegroundColor Yellow
    Write-Host "  |  This will take several minutes...         |" -ForegroundColor Yellow
    Write-Host "  =============================================" -ForegroundColor Yellow
    Write-Host ""
    
    Run-Pip $PIP_EXE @("install","--isolated","torch==2.5.1+cu121","torchaudio==2.5.1+cu121","--extra-index-url",$TORCH_IDX) "Installing PyTorch (CUDA 12.1)..."
    
    $tt2 = Quick-Test $VENV_PY @("-c","import torch; print(torch.__version__)")
    if ($tt2.OK) { WOK "PyTorch installed: $($tt2.Out)" }
    else { WWRN "PyTorch may have issues" }
}

if (-not $pkgsOK) {
    Run-Pip $PIP_EXE @("install","--isolated",$($PIP_PKGS -join " ")) "Installing packages..."
    
    $reqFile = Join-Path $PLUG_DIR "requirements.txt"
    if (Test-Path $reqFile) {
        Run-Pip $PIP_EXE @("install","--isolated","-r","`"$reqFile`"") "Installing from requirements.txt..."
    }
    WOK "Packages installed"
}

# ═══════════════════════════════════════════════════════════
#  STEP 10: Silero VAD
# ═══════════════════════════════════════════════════════════
WHDR 10 $TOTAL "Silero VAD model"

$silero = Join-Path $PLUG_DIR "ai_models\silero_vad.onnx"
if (Test-Path $silero) {
    WOK "Silero model exists"
    
    # Cache copy
    $cacheDir = Join-Path $env:USERPROFILE ".cache\torch\hub\snakers4_silero-vad_master\src\silero_vad\data"
    $cacheFile = Join-Path $cacheDir "silero_vad.onnx"
    if (-not (Test-Path $cacheFile)) {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        Copy-Item $silero $cacheFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $cacheFile) { WOK "Model copied to cache" }
    }
    
    # Patch detector
    $det = Join-Path $PLUG_DIR "speech_detection\silero_detector.py"
    if (Test-Path $det) {
        $dc = [System.IO.File]::ReadAllText($det, [System.Text.Encoding]::UTF8)
        if ($dc -match "_SILERO_LOCAL|_ONNX_MODEL_LOCAL|_BUNDLED_MODEL") {
            WSKP "silero_detector.py already patched"
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
} else {
    WWRN "Silero model not in ai_models/"
}

# ═══════════════════════════════════════════════════════════
#  STEP 11: Film Impact (optional)
# ═══════════════════════════════════════════════════════════
WHDR 11 $TOTAL "Film Impact"

if (Test-Path "C:\Program Files\Common Files\Adobe\CEP\extensions\Film Impact Dashboard") {
    WSKP "Film Impact already installed"
} else {
    $fiUrl = $null
    try {
        $lr = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" -UseBasicParsing
        $fa = $lr.assets | Where-Object { $_.name -match 'Film.*Impact.*\.exe$' } | Select-Object -First 1
        if ($fa) { $fiUrl = $fa.browser_download_url }
    } catch {}
    
    if ($fiUrl) {
        $fiInst = "$TEMP_DIR\FilmImpact-Setup.exe"
        WINF "Downloading Film Impact..."
        $dlOK = Safe-Download $fiUrl $fiInst 1000000
        if ($dlOK) {
            WINF "Installing..."
            Start-Process -FilePath $fiInst -ArgumentList "/VERYSILENT","/NORESTART" -Wait -NoNewWindow
            if (Test-Path "C:\Program Files\Common Files\Adobe\CEP\extensions\Film Impact Dashboard") { WOK "Film Impact installed" }
            else { WWRN "May need manual install" }
        }
    } else {
        WSKP "Film Impact not in release assets"
    }
}

# ═══════════════════════════════════════════════════════════
#  STEP 12: VERIFICATION
# ═══════════════════════════════════════════════════════════
WHDR 12 $TOTAL "Final Verification"

Write-Host ""
$allOK = $true; $fail = 0; $pass = 0

# Files
Write-Host "  --- Plugin Files ---" -ForegroundColor White
foreach ($f in @("index.html","CSXS\manifest.xml","host\premiere.jsx","scripts\backend_server.pyc","scripts\process_video.pyc","version.json","activation-gate.js","requirements.txt","template-engine.js","icon.png","ai_models\silero_vad.onnx","broll-server\server.js")) {
    if (Test-Path (Join-Path $PLUG_DIR $f)) { WOK $f; $pass++ }
    else { WERR "$f MISSING"; $allOK = $false; $fail++ }
}

# node_modules
if (Test-Path (Join-Path $PLUG_DIR "broll-server\node_modules")) { WOK "broll-server/node_modules"; $pass++ }
else { WERR "broll-server/node_modules MISSING"; $fail++ }

# Dirs
Write-Host ""
Write-Host "  --- Directories ---" -ForegroundColor White
foreach ($d in @("activation-server","ai_models","audio_engine","broll-server","core","CSXS","host","jsx","lib","panel","scripts","silence_detection","speech_detection","vendor","video_engine","waveform_analysis")) {
    if (Test-Path (Join-Path $PLUG_DIR $d)) { WOK $d; $pass++ }
    else { WERR "$d MISSING"; $allOK = $false; $fail++ }
}

# Runtime
Write-Host ""
Write-Host "  --- Runtime ---" -ForegroundColor White
if (Test-Path $PY_EXE) { WOK "Python"; $pass++ } else { WERR "Python"; $fail++ }
if (Test-Path $VENV_PY) { WOK ".venv"; $pass++ } else { WERR ".venv"; $fail++ }
if (Test-Path $NODE_EXE) { WOK "Node.js"; $pass++ } else { WWRN "Node.js" }

$ffCheck = $false
try { $null = Get-Command ffmpeg -ErrorAction Stop; $ffCheck = $true } catch {}
if (-not $ffCheck -and (Test-Path "C:\ffmpeg\ffmpeg.exe")) { $ffCheck = $true }
if ($ffCheck) { WOK "FFmpeg"; $pass++ } else { WWRN "FFmpeg"; $fail++ }

$cepOK2 = $true
foreach ($v in @("9","10","11","12")) {
    $val = (Get-ItemProperty -Path "HKCU:\Software\Adobe\CSXS.$v" -Name "PlayerDebugMode" -ErrorAction SilentlyContinue).PlayerDebugMode
    if ($val -ne "1") { $cepOK2 = $false }
}
if ($cepOK2) { WOK "CEP Debug"; $pass++ } else { WERR "CEP Debug"; $fail++ }

# Imports
Write-Host ""
Write-Host "  --- Package Imports ---" -ForegroundColor White
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
    $r = Quick-Test $VENV_PY @("-c",$pkg.C)
    if ($r.OK) { WOK "$($pkg.N) $($r.Out)"; $pass++ }
    else { WERR "$($pkg.N) FAILED"; $fail++ }
}

# Cleanup
Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

# Result
Write-Host ""
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  +=============================================+" -ForegroundColor Green
    Write-Host "  |                                             |" -ForegroundColor Green
    Write-Host "  |  [OK] INSTALLATION COMPLETE                 |" -ForegroundColor Green
    Write-Host "  |  [OK] $pass/$total checks passed                     |" -ForegroundColor Green
    Write-Host "  |                                             |" -ForegroundColor Green
    Write-Host "  |  1. Restart Premiere Pro                    |" -ForegroundColor Green
    Write-Host "  |  2. Window > Extensions > HALEEM-ULTRA      |" -ForegroundColor Green
    Write-Host "  |                                             |" -ForegroundColor Green
    Write-Host "  +=============================================+" -ForegroundColor Green
} elseif ($fail -le 3) {
    Write-Host "  +=============================================+" -ForegroundColor Yellow
    Write-Host "  |  [!!] $pass/$total passed, $fail warnings              |" -ForegroundColor Yellow
    Write-Host "  |  Review warnings above                      |" -ForegroundColor Yellow
    Write-Host "  +=============================================+" -ForegroundColor Yellow
} else {
    Write-Host "  +=============================================+" -ForegroundColor Red
    Write-Host "  |  [XX] $pass/$total passed, $fail failures              |" -ForegroundColor Red
    Write-Host "  |  Contact support with screenshot            |" -ForegroundColor Red
    Write-Host "  +=============================================+" -ForegroundColor Red
}
Write-Host ""
