@echo off
setlocal enabledelayedexpansion

REM build.bat - Auto increment version and build/run APP
REM Usage: build.bat [apk|aab|ipa|run]

set "BUILD_TYPE=%~1"
if "%BUILD_TYPE%"=="" set "BUILD_TYPE=apk"

if not exist "pubspec.yaml" (
    echo Error: pubspec.yaml not found
    exit /b 1
)

REM Read current version from pubspec.yaml
for /f "tokens=1,2" %%a in ('findstr /b "version:" pubspec.yaml') do (
    set "VERSION_FULL=%%b"
)

for /f "tokens=1 delims=+" %%a in ("!VERSION_FULL!") do set "VERSION_NAME=%%a"
for /f "tokens=2 delims=+" %%a in ("!VERSION_FULL!") do set "BUILD_NUM=%%a"

if not defined BUILD_NUM (
    echo Error: Cannot parse version from pubspec.yaml
    exit /b 1
)

REM Increment build number
set /a "NEW_BUILD_NUM=!BUILD_NUM!+1"
set "NEW_VERSION=!VERSION_NAME!+!NEW_BUILD_NUM!"

echo Version: !VERSION_NAME!+!BUILD_NUM! -^> !NEW_VERSION!

REM Update pubspec.yaml (ASCII safe with findstr)
set "TEMP_FILE=pubspec.yaml.tmp"
(
    for /f "usebackq delims=" %%a in ("pubspec.yaml") do (
        set "line=%%a"
        echo !line! | findstr /b "version:" >nul 2>&1
        if !errorlevel! equ 0 (
            echo version: !NEW_VERSION!
        ) else (
            echo !line!
        )
    )
) > "!TEMP_FILE!"
move /y "!TEMP_FILE!" "pubspec.yaml" >nul

if /i "!BUILD_TYPE!"=="run" (
    echo Running app with flutter run...
    flutter run
    goto :eof
)

echo Building !BUILD_TYPE!...

if /i "!BUILD_TYPE!"=="apk" (
    flutter clean
    flutter build apk --release
    flutter build apk --release --split-per-abi
    goto :done
)

if /i "!BUILD_TYPE!"=="aab" (
    flutter build appbundle --release
    echo AAB: build\app\outputs\bundle\release\app-release.aab
    goto :done
)

if /i "!BUILD_TYPE!"=="ipa" (
    flutter build ipa --release
    echo IPA: build\ios\ipa\*.ipa
    goto :done
)

echo Usage: build.bat [apk^|aab^|ipa^|run]
exit /b 1

:done
echo Build complete: !NEW_VERSION!

endlocal
