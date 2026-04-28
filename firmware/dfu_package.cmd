@echo off
setlocal enabledelayedexpansion

REM dfu_package.cmd - Generate DFU firmware package (application only)
REM Usage: dfu_package.cmd <version> [output_name]
REM Example: dfu_package.cmd 2.2.0 firmware_v2.2.0.zip
REM Note: Version string like "2.2.0" will be converted to integer "20200" for nrfutil

set "VERSION_STR=%~1"
if "%VERSION_STR%"=="" set "VERSION_STR=1.0.0"

set "OUTPUT=%~2"
if "%OUTPUT%"=="" set "OUTPUT=firmware_v%VERSION_STR%.zip"

set "HEX_FILE=_build\nrf52832_xxaa.hex"
set "PRIVATE_KEY=private.pem"

REM Check firmware file
if not exist "%HEX_FILE%" (
    echo Error: %HEX_FILE% not found
    echo Please run 'make' first to build the firmware
    exit /b 1
)

REM Check private key
if not exist "%PRIVATE_KEY%" (
    echo Generating signing key...
    nrfutil keys generate "%PRIVATE_KEY%"
    if errorlevel 1 (
        echo Error: Failed to generate key
        exit /b 1
    )
    echo Key generated: %PRIVATE_KEY%
)

REM Convert version string to integer (e.g., 2.2.0 -> 20200)
set "VERSION_INT=0"
for /f "tokens=1,2,3 delims=." %%a in ("%VERSION_STR%") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set "PATCH=%%c"
)
if not defined MINOR set "MINOR=0"
if not defined PATCH set "PATCH=0"
set /a "VERSION_INT=MAJOR*10000+MINOR*100+PATCH"

REM Generate DFU package (application only)
REM Note: Using 0x0101 - actual SoftDevice FWID from device
echo Generating DFU package...
echo Version: %VERSION_STR% (integer: %VERSION_INT%)
nrfutil pkg generate --application "%HEX_FILE%" --application-version "%VERSION_INT%" --hw-version 52 --sd-req 0x0101 --key-file "%PRIVATE_KEY%" "%OUTPUT%"

if errorlevel 1 (
    echo Error: Failed to generate DFU package
    exit /b 1
)

REM Generate settings hex for flashing
echo.
echo Generating settings.hex...
nrfutil settings generate --family NRF52 --application "%HEX_FILE%" --application-version "%VERSION_INT%" --bootloader-version 1 --bl-settings-version 2 settings.hex

echo.
echo ========================================
echo  DFU Package Generation Complete
echo ========================================
echo.
echo DFU Package: %OUTPUT%
echo Version: %VERSION_STR% (%VERSION_INT%)
echo SoftDevice: 0x0101 (from device)
echo.
echo Files to flash:
echo   1. secure_bootloader.hex  - Bootloader (0x78000)
echo   2. %HEX_FILE% - Application (0x26000)
echo   3. settings.hex - Settings (0x7F000)
echo.
echo Upload %OUTPUT% to your server for OTA updates.
echo.

endlocal
