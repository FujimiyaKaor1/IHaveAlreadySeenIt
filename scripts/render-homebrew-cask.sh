#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEMPLATE="$ROOT/Packaging/Homebrew/ihavealreadyseenit.rb.in"
VERSION="${1:-}"
SHA256="${2:-}"
OUTPUT="${3:-$ROOT/Casks/ihavealreadyseenit.rb}"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "Version must be a stable semantic version such as 1.0.1"
    exit 2
fi
if [[ ! "$SHA256" =~ '^[0-9a-f]{64}$' ]]; then
    print -u2 "SHA-256 must contain exactly 64 lowercase hexadecimal characters"
    exit 2
fi
if [[ -z "$OUTPUT" || "$OUTPUT" == *$'\n'* || -L "$OUTPUT" ]]; then
    print -u2 "Output must be a regular, non-symbolic-link path"
    exit 2
fi
if [[ ! -f "$TEMPLATE" ]]; then
    print -u2 "Missing Homebrew Cask template: $TEMPLATE"
    exit 2
fi

mkdir -p "${OUTPUT:h}"
TEMPORARY="$(mktemp "${TMPDIR:-/tmp}/ihavealreadyseenit-cask.XXXXXX")"
trap 'rm -f "$TEMPORARY"' EXIT
sed -e "s/__VERSION__/$VERSION/g" -e "s/__SHA256__/$SHA256/g" \
    "$TEMPLATE" > "$TEMPORARY"
install -m 644 "$TEMPORARY" "$OUTPUT"
print "$OUTPUT"
