# dfu_package.ps1 - Generate DFU firmware package (application only)
# Usage: ./dfu_package.ps1 <version> [output_name]
# Example: ./dfu_package.ps1 2.2.0 firmware_v2.2.0.zip
# Note: Version string like "2.2.0" will be converted to integer "20200" for nrfutil

param(
    [string]$VersionStr = "1.0.0",
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"

$HEX_FILE = "_build\nrf52832_xxaa.hex"
$PRIVATE_KEY = "private.pem"

if ($Output -eq "") {
    $Output = "firmware_v${VersionStr}.zip"
}

# Check firmware file
if (-not (Test-Path $HEX_FILE)) {
    Write-Error "Error: $HEX_FILE not found"
    Write-Host "Please run 'make' first to build the firmware"
    exit 1
}

# Check private key
if (-not (Test-Path $PRIVATE_KEY)) {
    Write-Host "Generating signing key..."
    & nrfutil keys generate $PRIVATE_KEY
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error: Failed to generate key"
        exit 1
    }
    Write-Host "Key generated: $PRIVATE_KEY"
}

# Convert version string to integer (e.g., 2.2.0 -> 20200)
$versionParts = $VersionStr.Split('.')
$major = [int]$versionParts[0]
$minor = if ($versionParts.Count -gt 1) { [int]$versionParts[1] } else { 0 }
$patch = if ($versionParts.Count -gt 2) { [int]$versionParts[2] } else { 0 }
$versionInt = $major * 10000 + $minor * 100 + $patch

# Generate DFU package (application only)
Write-Host "Generating DFU package..."
Write-Host "Version: $VersionStr (integer: $versionInt)"
& nrfutil pkg generate --application $HEX_FILE --application-version $versionInt --hw-version 52 --sd-req 0xCB --key-file $PRIVATE_KEY $Output

if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to generate DFU package"
    exit 1
}

Write-Host ""
Write-Host "DFU package created: $Output"
Write-Host "Version: $VersionStr ($versionInt)"
Write-Host "SoftDevice: S132 v7.3.0 (0xCB)"
