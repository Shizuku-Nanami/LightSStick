@echo off
setlocal enabledelayedexpansion

REM flash_app.cmd - Flash Application only (for third-party flashers)
REM Usage: flash_app.cmd [hex_file]
REM Default: _build\nrf52832_xxaa.hex

set "HEX_FILE=%~1"
if "%HEX_FILE%"=="" set "HEX_FILE=_build\nrf52832_xxaa.hex"

if not exist "%HEX_FILE%" (
    echo Error: %HEX_FILE% not found
    echo Please run 'make' first to build the firmware
    exit /b 1
)

echo ========================================
echo  HikariStick Application Flash
echo ========================================
echo.
echo Hex file: %HEX_FILE%
echo.
echo Memory layout:
echo   Application starts at: 0x26000
echo   Application ends at:   0x77FFF
echo.
echo Please use your flash tool to program this hex file.
echo Make sure to:
echo   1. Erase flash first (or use sector erase)
echo   2. Program at address 0x26000
echo.
echo After flashing, the device will:
echo   - Initialize the bootloader UICR on first boot
echo   - Start the application
echo.
echo To enter DFU mode later:
echo   - Use APP's firmware update feature
echo   - Or send 'DFU' command via BLE (FFF7 characteristic)
echo.

endlocal
