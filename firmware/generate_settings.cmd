@echo off
setlocal enabledelayedexpansion

REM generate_settings.cmd - Generate DFU settings hex file
REM Usage: generate_settings.cmd [version] [hex_file]
REM Example: generate_settings.cmd 2.2.0 _build/nrf52832_xxaa.hex

set "VERSION_STR=%~1"
if "%VERSION_STR%"=="" set "VERSION_STR=2.2.0"

set "HEX_FILE=%~2"
if "%HEX_FILE%"=="" set "HEX_FILE=_build\nrf52832_xxaa.hex"

if not exist "%HEX_FILE%" (
    echo Error: %HEX_FILE% not found
    echo Please run 'make' first to build the firmware
    exit /b 1
)

REM Convert version string to integer
for /f "tokens=1,2,3 delims=." %%a in ("%VERSION_STR%") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set "PATCH=%%c"
)
if not defined MINOR set "MINOR=0"
if not defined PATCH set "PATCH=0"
set /a "VERSION_INT=MAJOR*10000+MINOR*100+PATCH"

echo Generating DFU settings...
echo Version: %VERSION_STR% (%VERSION_INT%)

nrfutil settings generate ^
    --family NRF52 ^
    --application "%HEX_FILE%" ^
    --application-version "%VERSION_INT%" ^
    --bootloader-version 1 ^
    --bl-settings-version 2 ^
    settings.hex

if errorlevel 1 (
    echo Error: Failed to generate settings
    exit /b 1
)

echo.
echo Settings generated: settings.hex
echo Flash to address: 0x7F000

endlocal
