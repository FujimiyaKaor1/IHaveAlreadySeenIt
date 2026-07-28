#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CASK="$ROOT/Packaging/Homebrew/Casks/ihavealreadyseenit.rb"
TAP="ihavealreadyseenit-smoke-$$/tap"
TOKEN="$TAP/ihavealreadyseenit"
TEMPORARY="$(mktemp -d "${TMPDIR:-/tmp}/ihavealreadyseenit-homebrew.XXXXXX")"
APP_DIRECTORY="$TEMPORARY/Applications"
APP="$APP_DIRECTORY/IHaveAlreadySeenIt.app"
BACKUP_EXECUTABLE="/Applications/.IHaveAlreadySeenItBackup/Original-WeChat.bundle/Contents/MacOS/WeChat"
CREATED_TAP=0
INSTALLED_CASK=0

cleanup() {
    if (( INSTALLED_CASK )); then
        brew uninstall --cask "$TOKEN" >/dev/null 2>&1 || true
    fi
    brew untrust --cask "$TOKEN" >/dev/null 2>&1 || true
    if (( CREATED_TAP )); then
        brew untap "$TAP" >/dev/null 2>&1 || true
    fi
    if [[ -d "$TEMPORARY" ]]; then
        find "$TEMPORARY" -depth -delete
    fi
}
trap cleanup EXIT

if brew list --cask --versions ihavealreadyseenit >/dev/null 2>&1; then
    print -u2 "Refusing to run while ihavealreadyseenit is already managed by Homebrew"
    exit 2
fi
if [[ ! -f "$CASK" || -L "$CASK" ]]; then
    print -u2 "Missing reviewed Homebrew Cask: $CASK"
    exit 2
fi

mkdir -p "$APP_DIRECTORY"
BACKUP_HASH=""
if [[ -f "$BACKUP_EXECUTABLE" ]]; then
    BACKUP_HASH="$(shasum -a 256 "$BACKUP_EXECUTABLE" | awk '{ print $1 }')"
fi

brew tap-new --no-git "$TAP" >/dev/null
CREATED_TAP=1
TAP_REPOSITORY="$(brew --repository "$TAP")"
mkdir -p "$TAP_REPOSITORY/Casks"
install -m 644 "$CASK" "$TAP_REPOSITORY/Casks/ihavealreadyseenit.rb"

brew install --cask --appdir="$APP_DIRECTORY" "$TOKEN"
INSTALLED_CASK=1
test -d "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
xattr -p com.apple.quarantine "$APP" >/dev/null
if spctl --assess --type execute "$APP" >/dev/null 2>&1; then
    print "Gatekeeper assessment is already approved for this account; quarantine remains present"
else
    print "Gatekeeper requires first-open confirmation, as expected for this Community build"
fi
"$APP/Contents/Helpers/ihavealreadyseenit" --help | grep -Fq 'doctor'

brew reinstall --cask --appdir="$APP_DIRECTORY" "$TOKEN"
test -d "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -n "$BACKUP_HASH" ]]; then
    test -f "$BACKUP_EXECUTABLE"
    test "$(shasum -a 256 "$BACKUP_EXECUTABLE" | awk '{ print $1 }')" = "$BACKUP_HASH"
fi

brew uninstall --cask "$TOKEN"
INSTALLED_CASK=0
test ! -e "$APP"
if [[ -n "$BACKUP_HASH" ]]; then
    test -f "$BACKUP_EXECUTABLE"
    test "$(shasum -a 256 "$BACKUP_EXECUTABLE" | awk '{ print $1 }')" = "$BACKUP_HASH"
fi

print "Homebrew install, reinstall, and uninstall smoke test passed"
