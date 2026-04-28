@echo off
setlocal enabledelayedexpansion

REM flash_all.cmd - Flash SoftDevice + Bootloader + Application
REM Usage: flash_all.cmd

set "SOFTDEVICE=C:\Other\nRF\nRF5_SDK_17.1.0_ddde560\components\softdevice\s132\hex\s132_nrf52_7.2.0_softdevice.hex"
set "BOOTLOADER=secure_bootloader.hex"
set "APPLICATION=_build\nrf52832_xxaa.hex"

REM Check files
if not exist "%SOFTDEVICE%" (
    echo Error: SoftDevice not found: %SOFTDEVICE%
    exit /b 1
)
if not exist "%BOOTLOADER%" (
    echo Error: Bootloader not found: %BOOTLOADER%
    exit /b 1
)
if not exist "%APPLICATION%" (
    echo Error: Application not found: %APPLICATION%
    echo Please run 'make' first
    exit /b 1
)

echo ========================================
echo  HikariStick DFU Firmware Flashing
echo ========================================
echo.
echo This will erase all data and flash:
echo   1. SoftDevice S132 v7.3.0
echo   2. Secure DFU Bootloader
echo   3. Application
echo.
pause

REM Erase all
echo [1/3] Erasing chip...
nrfjprog -f nrf52 --eraseall
if errorlevel 1 (
    echo Error: Failed to erase chip
    exit /b 1
)

REM Flash SoftDevice
echo [2/3] Flashing SoftDevice...
nrfjprog -f nrf52 --program "%SOFTDEVICE%" --sectorerase
if errorlevel 1 (
    echo Error: Failed to flash SoftDevice
    exit /b 1
)

REM Flash Bootloader
echo [3/4] Flashing Bootloader...
nrfjprog -f nrf52 --program "%BOOTLOADER%" --sectorerase
if errorlevel 1 (
    echo Error: Failed to flash Bootloader
    exit /b 1
)

REM Flash Application
echo [4/4] Flashing Application...
nrfjprog -f nrf52 --program "%APPLICATION%" --sectorerase
if errorlevel 1 (
    echo Error: Failed to flash Application
    exit /b 1
)

REM Reset
echo.
echo Resetting device...
nrfjprog -f nrf52 --reset

echo.
echo ========================================
echo  Flashing complete!
echo ========================================
echo.
echo Memory layout:
echo   0x00000 - MBR
echo   0x01000 - SoftDevice S132 v7.2.0
echo   0x26000 - Application
echo   0x78000 - Secure DFU Bootloader
echo   0x7F000 - Bootloader Settings
echo.
echo DFU is now ready to use!
echo.

endlocal
