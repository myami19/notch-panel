#!/bin/zsh
# Сборка Notch Panel без Xcode: ./build.sh
set -e
cd "$(dirname "$0")"

APP="build/NotchPanel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"

# SDK 27 в Command Line Tools новее компилятора, поэтому берём 26.x.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"

# Универсальная сборка: Apple Silicon + Intel, склеиваем в один файл.
for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $ARCH-apple-macos14.0 -sdk "$SDK" \
        Sources/*.swift -o "build/NotchPanel-$ARCH"
done
lipo -create build/NotchPanel-arm64 build/NotchPanel-x86_64 -output "$APP/Contents/MacOS/NotchPanel"
rm -f build/NotchPanel-arm64 build/NotchPanel-x86_64

codesign --force --sign - "$APP"
echo "Готово: $APP"
