#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DESTINATION="/Applications/IHaveAlreadySeenIt.app"

[[ "$(uname -s)" == "Darwin" ]] || { print -u2 "macOS is required"; exit 1; }
xcrun --find swift >/dev/null
xcrun --find codesign >/dev/null

BUILD_FLAVOR=community "$ROOT/scripts/package-app.sh"
if [[ ! -w /Applications ]]; then
    print -u2 "无法写入 /Applications。请在 Finder 中将 dist/IHaveAlreadySeenIt.app 拖入 Applications。"
    print -u2 "Cannot write /Applications. Drag dist/IHaveAlreadySeenIt.app there in Finder."
    exit 1
fi

if [[ "$(osascript -e 'application "IHaveAlreadySeenIt" is running' 2>/dev/null)" == "true" ]]; then
    osascript -e 'tell application "IHaveAlreadySeenIt" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        [[ "$(osascript -e 'application "IHaveAlreadySeenIt" is running' 2>/dev/null)" == "true" ]] || break
        sleep 0.25
    done
    if [[ "$(osascript -e 'application "IHaveAlreadySeenIt" is running' 2>/dev/null)" == "true" ]]; then
        print -u2 "IHaveAlreadySeenIt is still running. Quit it normally, then rerun this script."
        exit 1
    fi
fi

rm -rf "$DESTINATION.new"
ditto "$ROOT/dist/IHaveAlreadySeenIt.app" "$DESTINATION.new"
rm -rf "$DESTINATION"
mv "$DESTINATION.new" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
open "$DESTINATION"
print "Installed and opened $DESTINATION"
