#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="$ROOT/dist/IHaveAlreadySeenIt.app"

cd "$ROOT"
swift build -c release --product IHaveAlreadySeenItApp
swift build -c release --product IHaveAlreadySeenItPrivilegedHelper
swift build -c release --product ihavealreadyseenit
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    "$ROOT/Packaging/AppInfo.plist" > "$APP/Contents/Info.plist"
install -m 755 "$BIN_DIR/IHaveAlreadySeenItApp" "$APP/Contents/MacOS/IHaveAlreadySeenItApp"

RESOURCE_BUNDLE="$BIN_DIR/IHaveAlreadySeenIt_IHaveAlreadySeenItCore.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    print -u2 "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE"
    exit 1
fi
ditto "$RESOURCE_BUNDLE" "$APP/IHaveAlreadySeenIt_IHaveAlreadySeenItCore.bundle"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    if [[ -z "${DEVELOPER_TEAM_ID:-}" ]]; then
        print -u2 "DEVELOPER_TEAM_ID is required for a signed build"
        exit 1
    fi
    mkdir -p "$APP/Contents/Library/LaunchServices" "$APP/Contents/Library/LaunchDaemons"
    install -m 755 "$BIN_DIR/IHaveAlreadySeenItPrivilegedHelper" \
        "$APP/Contents/Library/LaunchServices/IHaveAlreadySeenItPrivilegedHelper"
    sed "s/__TEAM_ID__/$DEVELOPER_TEAM_ID/g" "$ROOT/Packaging/PrivilegedHelper.plist.in" > \
        "$APP/Contents/Library/LaunchDaemons/io.github.fujimiyakaor1.IHaveAlreadySeenIt.PrivilegedHelper.plist"

    codesign --force --timestamp --options runtime \
        --identifier io.github.fujimiyakaor1.IHaveAlreadySeenIt.PrivilegedHelper \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$APP/Contents/Library/LaunchServices/IHaveAlreadySeenItPrivilegedHelper"
    codesign --force --timestamp --options runtime \
        --entitlements "$ROOT/Packaging/App.entitlements" \
        --sign "$DEVELOPER_ID_APPLICATION" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
else
    print "Created an unsigned read-only preview; privileged install/restore is intentionally unavailable."
fi

print "$APP"
