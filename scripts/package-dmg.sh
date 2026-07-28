#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-1.0.0}"
STAGE="$ROOT/dist/dmg-root"
DMG="$ROOT/dist/IHaveAlreadySeenIt-$VERSION-Community.dmg"

BUILD_FLAVOR=community VERSION="$VERSION" "$ROOT/scripts/package-app.sh"
rm -rf "$STAGE" "$DMG" "$DMG.sha256"
mkdir -p "$STAGE"
ditto "$ROOT/dist/IHaveAlreadySeenIt.app" "$STAGE/IHaveAlreadySeenIt.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Packaging/FIRST_USE_zh-Hans.txt" "$STAGE/首次使用说明.txt"
cp "$ROOT/Packaging/FIRST_USE_en.txt" "$STAGE/First Use.txt"
cp "$ROOT/Packaging/GeneratedIcons/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true

# Normalize mtimes so identical source trees produce stable staged input.
find "$STAGE" -exec touch -h -t 202601010000 {} +
hdiutil create -quiet -fs HFS+ -format UDZO -imagekey zlib-level=9 \
    -volname "IHaveAlreadySeenIt Community" -srcfolder "$STAGE" "$DMG"
(cd "$ROOT/dist" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
rm -rf "$STAGE"
print "$DMG"
