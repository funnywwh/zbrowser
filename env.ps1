# PowerShell script to set up Zig environment
# Get the script directory
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# Add the project local Zig compiler path to the front of PATH
$ZIG_PATH = Join-Path $SCRIPT_DIR "zig-x86_64-windows-0.15.2"
$env:PATH = "$ZIG_PATH;$env:PATH"

# Verify Zig version is 0.15.2
$REQUIRED_VERSION = "0.15.2"

# Check if zig.exe exists
if (-not (Test-Path "$ZIG_PATH\zig.exe")) {
    Write-Host "Error: zig.exe not found!" -ForegroundColor Red
    Write-Host "  Please ensure $ZIG_PATH\zig.exe exists" -ForegroundColor Red
    exit 1
}

# Get Zig version
try {
    $ACTUAL_VERSION = & "$ZIG_PATH\zig.exe" version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get version"
    }
} catch {
    Write-Host "Error: Unable to get Zig version!" -ForegroundColor Red
    Write-Host "  Please ensure $ZIG_PATH\zig.exe is executable" -ForegroundColor Red
    exit 1
}

if ($ACTUAL_VERSION -ne $REQUIRED_VERSION) {
    Write-Host "Warning: Zig version mismatch!" -ForegroundColor Yellow
    Write-Host "  Required version: $REQUIRED_VERSION" -ForegroundColor Yellow
    Write-Host "  Actual version: $ACTUAL_VERSION" -ForegroundColor Yellow
    Write-Host "  Please ensure $ZIG_PATH\zig.exe has the correct version" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "[OK] Zig version verified: $ACTUAL_VERSION" -ForegroundColor Green
}

