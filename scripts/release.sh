#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:?Set VERSION, for example VERSION=1.0.0}"

"$ROOT/scripts/coverage.sh"
VERSION="$VERSION" "$ROOT/scripts/package-dmg.sh"

SOURCE="$ROOT/dist/IHaveAlreadySeenIt-$VERSION-source.tar.gz"
rm -f "$SOURCE" "$SOURCE.sha256"
git -C "$ROOT" archive --format=tar.gz --prefix="IHaveAlreadySeenIt-$VERSION/" -o "$SOURCE" HEAD
(cd "$ROOT/dist" && shasum -a 256 "${SOURCE:t}" > "${SOURCE:t}.sha256")

print "$ROOT/dist/IHaveAlreadySeenIt-$VERSION-Community.dmg"
print "$SOURCE"
