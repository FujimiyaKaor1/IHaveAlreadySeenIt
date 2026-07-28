#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_FLAVOR="${BUILD_FLAVOR:-community}"
APP="$ROOT/dist/IHaveAlreadySeenIt.app"

if [[ "$BUILD_FLAVOR" != "community" && "$BUILD_FLAVOR" != "read-only" ]]; then
    print -u2 "BUILD_FLAVOR must be community or read-only"
    exit 1
fi

cd "$ROOT"
APP_SWIFT_FLAGS=()
if [[ "$BUILD_FLAVOR" == "community" ]]; then
    APP_SWIFT_FLAGS=(-Xswiftc -DIHAVEALREADYSEENIT_LOCAL_DEVELOPMENT)
fi

swift build -c release --product IHaveAlreadySeenItApp "${APP_SWIFT_FLAGS[@]}"
swift build -c release --product ihavealreadyseenit
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
APP_RESOURCES="$APP/Contents/Resources"
CORE_BUNDLE="$APP_RESOURCES/IHaveAlreadySeenIt_IHaveAlreadySeenItCore.bundle"
APP_BUNDLE="$APP_RESOURCES/IHaveAlreadySeenIt_IHaveAlreadySeenItApp.bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP_RESOURCES"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    "$ROOT/Packaging/AppInfo.plist" > "$APP/Contents/Info.plist"
install -m 755 "$BIN_DIR/IHaveAlreadySeenItApp" "$APP/Contents/MacOS/IHaveAlreadySeenItApp"
install -m 755 "$BIN_DIR/ihavealreadyseenit" "$APP/Contents/Helpers/ihavealreadyseenit"

for bundle in \
    "$BIN_DIR/IHaveAlreadySeenIt_IHaveAlreadySeenItCore.bundle" \
    "$BIN_DIR/IHaveAlreadySeenIt_IHaveAlreadySeenItApp.bundle"; do
    if [[ ! -d "$bundle" ]]; then
        print -u2 "Missing SwiftPM resource bundle: $bundle"
        exit 1
    fi
    destination="$APP_RESOURCES/${bundle:t}"
    ditto "$bundle" "$destination"
done

test -d "$CORE_BUNDLE"
test -d "$APP_BUNDLE"
test -f "$CORE_BUNDLE/AntiRevokeHook.c"
test -f "$CORE_BUNDLE/IHaveAlreadySeenIt.entitlements"
test -f "$APP_BUNDLE/CommunityBackground.jpg"
test -f "$APP_BUNDLE/zh-Hans.lproj/Localizable.strings"
test -f "$APP_BUNDLE/en.lproj/Localizable.strings"

install -m 644 "$ROOT/Packaging/GeneratedIcons/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
install -m 644 "$ROOT/Packaging/GeneratedIcons/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"

# Community builds never contain or register the privileged helper. The embedded CLI is
# the only administrator boundary and accepts a fixed, audited command surface.
if find "$APP" -iname '*PrivilegedHelper*' -print -quit | grep -q .; then
    print -u2 "Community package unexpectedly contains a privileged helper"
    exit 1
fi

# Sign nested executables first, then seal the complete bundle with an ad-hoc identity.
codesign --force --sign - "$APP/Contents/Helpers/ihavealreadyseenit"
codesign --force --sign - "$APP/Contents/MacOS/IHaveAlreadySeenItApp"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

print "Created $BUILD_FLAVOR Community package: $APP"
