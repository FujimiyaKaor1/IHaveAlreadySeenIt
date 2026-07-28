#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:?Set VERSION, for example VERSION=0.2.0}"
ARCHIVE="$ROOT/dist/IHaveAlreadySeenIt-$VERSION.app.zip"
OUTPUT="$ROOT/dist/ihavealreadyseenit.rb"

if [[ ! -f "$ARCHIVE" ]]; then
    print -u2 "Missing release archive: $ARCHIVE"
    exit 1
fi

SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__SHA256__/$SHA256/g" \
    "$ROOT/Casks/ihavealreadyseenit.rb.in" > "$OUTPUT"
print "$OUTPUT"
