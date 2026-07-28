#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:?Set VERSION, for example VERSION=0.2.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a keychain profile created with notarytool}"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${DEVELOPER_TEAM_ID:-}" ]]; then
    print -u2 "DEVELOPER_ID_APPLICATION and DEVELOPER_TEAM_ID are required"
    exit 1
fi

"$ROOT/scripts/package-app.sh"
ARCHIVE="$ROOT/dist/IHaveAlreadySeenIt-$VERSION.app.zip"
rm -f "$ARCHIVE" "$ARCHIVE.sha256"
ditto -c -k --keepParent "$ROOT/dist/IHaveAlreadySeenIt.app" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$ROOT/dist/IHaveAlreadySeenIt.app"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$ROOT/dist/IHaveAlreadySeenIt.app" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
"$ROOT/scripts/render-cask.sh"
print "$ARCHIVE"
