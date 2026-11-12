#!/bin/zsh
# Собирает DMG для друзей: ./make-dmg.sh  →  dist/Notch Panel <версия>.dmg
set -e
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
STAGE="build/dmg"
OUT="dist/Notch Panel $VERSION.dmg"

rm -rf "$STAGE"; mkdir -p "$STAGE" dist
ditto build/NotchPanel.app "$STAGE/Notch Panel.app"
ln -s /Applications "$STAGE/Applications"
cp "dist-files/Как установить.txt" "$STAGE/"

rm -f "$OUT"
hdiutil create -volname "Notch Panel" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
rm -rf "$STAGE"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
