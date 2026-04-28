#!/bin/bash
# build.sh - 自动递增版本号并构建 APP
# 用法: ./build.sh [apk|aab|ipa]

set -e

BUILD_TYPE="${1:-apk}"
PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Error: $PUBSPEC not found"
    exit 1
fi

# 读取当前版本
VERSION_LINE=$(grep "^version:" "$PUBSPEC")
VERSION_NAME=$(echo "$VERSION_LINE" | sed 's/version: \([0-9.]*\)+.*/\1/')
BUILD_NUM=$(echo "$VERSION_LINE" | sed 's/version: [0-9.]*+\([0-9]*\)/\1/')

# 递增 build number
NEW_BUILD_NUM=$((BUILD_NUM + 1))
NEW_VERSION="${VERSION_NAME}+${NEW_BUILD_NUM}"

echo "Version: $VERSION_NAME+$BUILD_NUM -> $NEW_VERSION"

# 更新 pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"

echo "Building $BUILD_TYPE..."

case "$BUILD_TYPE" in
    apk)
        flutter build apk --release
        echo "APK: build/app/outputs/flutter-apk/app-release.apk"
        ;;
    aab)
        flutter build appbundle --release
        echo "AAB: build/app/outputs/bundle/release/app-release.aab"
        ;;
    ipa)
        flutter build ipa --release
        echo "IPA: build/ios/ipa/*.ipa"
        ;;
    *)
        echo "Usage: $0 [apk|aab|ipa]"
        exit 1
        ;;
esac

echo "Build complete: $NEW_VERSION"
