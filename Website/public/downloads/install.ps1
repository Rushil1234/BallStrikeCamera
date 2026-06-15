# TrueCarry Bridge — one-command installer for Windows (PowerShell).
# Run with:  irm https://truecarry.vercel.app/downloads/install.ps1 | iex
#
# Running from the web with iex means nothing is downloaded as a blocked .exe,
# so there's no SmartScreen "unrecognized app" wall. It sets up an isolated
# Python environment, installs the one dependency, and launches the bridge.

$ErrorActionPreference = "Stop"
$BaseUrl = "https://truecarry.vercel.app/downloads"
$Dir = Join-Path $env:USERPROFILE ".truecarry"

Write-Host "============================================"
Write-Host "  TrueCarry Bridge"
Write-Host "============================================"
Write-Host ""

# 1. Python 3
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Python 3 is required."
    Write-Host "Install it from https://www.python.org/downloads/ (check 'Add Python to PATH'),"
    Write-Host "then run this command again."
    return
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

# 2. Isolated environment
$VenvPy = Join-Path $Dir "venv\Scripts\python.exe"
if (-not (Test-Path $VenvPy)) {
    Write-Host "Setting up (first time only)..."
    python -m venv (Join-Path $Dir "venv")
}

# 3. Dependency — only install if missing
& $VenvPy -c "import bleak" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Bluetooth library..."
    & (Join-Path $Dir "venv\Scripts\pip.exe") install --quiet bleak
}

# 4. Always fetch the latest bridge
Invoke-WebRequest -UseBasicParsing "$BaseUrl/bridge.py" -OutFile (Join-Path $Dir "bridge.py")

# 5. Run it
Write-Host ""
& $VenvPy (Join-Path $Dir "bridge.py")
