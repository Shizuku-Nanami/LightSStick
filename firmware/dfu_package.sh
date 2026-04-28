#!/bin/bash
# dfu_package.sh - Generate DFU firmware package (application only)
# Usage: ./dfu_package.sh <version> [output_name]
# Example: ./dfu_package.sh 2.2.0 firmware_v2.2.0.zip
# Note: Version string like "2.2.0" will be converted to integer "20200" for nrfutil

set -e

VERSION_STR="${1:-1.0.0}"
OUTPUT="${2:-firmware_v${VERSION_STR}.zip}"
HEX_FILE="_build/nrf52832_xxaa.hex"
PRIVATE_KEY="private.pem"

# Check firmware file
if [ ! -f "$HEX_FILE" ]; then
    echo "Error: $HEX_FILE not found"
    echo "Please run 'make' first to build the firmware"
    exit 1
fi

# Check private key
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Generating signing key..."
    nrfutil keys generate "$PRIVATE_KEY"
    echo "Key generated: $PRIVATE_KEY"
fi

# Convert version string to integer (e.g., 2.2.0 -> 20200)
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION_STR"
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}
VERSION_INT=$((MAJOR * 10000 + MINOR * 100 + PATCH))

# Generate DFU package (application only)
echo "Generating DFU package..."
echo "Version: $VERSION_STR (integer: $VERSION_INT)"
nrfutil pkg generate \
    --application "$HEX_FILE" \
    --application-version "$VERSION_INT" \
    --hw-version 52 \
    --sd-req 0xCB \
    --key-file "$PRIVATE_KEY" \
    "$OUTPUT"

echo ""
echo "DFU package created: $OUTPUT"
echo "Version: $VERSION_STR ($VERSION_INT)"
echo "SoftDevice: S132 v7.3.0 (0xCB)"
