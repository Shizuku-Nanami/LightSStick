# build.ps1 - 自动递增版本号并构建/运行 APP
# 用法: ./build.ps1 [apk|aab|ipa|run]

param(
    [ValidateSet("apk", "aab", "ipa", "run", "")]
    [string]$BuildType = "apk"
)

$ErrorActionPreference = "Stop"

$PUBSPEC = "pubspec.yaml"

if (-not (Test-Path $PUBSPEC)) {
    Write-Error "Error: $PUBSPEC not found"
    exit 1
}

# 读取当前版本
$versionLine = (Get-Content $PUBSPEC | Select-String "^version:").Line
if ($versionLine -match 'version:\s*([0-9.]+)\+([0-9]+)') {
    $versionName = $Matches[1]
    $buildNum = [int]$Matches[2]
} else {
    Write-Error "Error: Cannot parse version from $PUBSPEC"
    exit 1
}

# 递增 build number
$newBuildNum = $buildNum + 1
$newVersion = "$versionName+$newBuildNum"

Write-Host "Version: $versionName+$buildNum -> $newVersion"

# 更新 pubspec.yaml
$content = Get-Content $PUBSPEC -Raw
$content = $content -replace '(?m)^version:\s*.*', "version: $newVersion"
Set-Content $PUBSPEC -Value $content -NoNewline

if ($BuildType -eq "run") {
    Write-Host "Running app with flutter run..."
    flutter run
} else {
    Write-Host "Building $BuildType..."

    switch ($BuildType) {
        "apk" {
            flutter build apk --release
            Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk"
        }
        "aab" {
            flutter build appbundle --release
            Write-Host "AAB: build/app/outputs/bundle/release/app-release.aab"
        }
        "ipa" {
            flutter build ipa --release
            Write-Host "IPA: build/ios/ipa/*.ipa"
        }
    }

    Write-Host "Build complete: $newVersion"
}
