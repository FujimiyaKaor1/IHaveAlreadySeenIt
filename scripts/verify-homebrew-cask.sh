#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CASK="${1:-$ROOT/Casks/ihavealreadyseenit.rb}"

if [[ ! -f "$CASK" || -L "$CASK" ]]; then
    print -u2 "Cask must be a regular file: $CASK"
    exit 2
fi

ruby -c "$CASK" >/dev/null

required=(
    'cask "ihavealreadyseenit" do'
    'depends_on macos: :sonoma'
    'app "IHaveAlreadySeenIt.app"'
    'brew uninstall --cask ihavealreadyseenit'
    'Homebrew does not bypass Gatekeeper'
)
for value in "${required[@]}"; do
    if ! grep -Fq "$value" "$CASK"; then
        print -u2 "Cask is missing required content: $value"
        exit 2
    fi
done

if grep -Eq 'no_quarantine|uninstall_preflight|(^|[[:space:]])system[[:space:]]|sudo|xattr|curl[[:space:]].*\|' "$CASK"; then
    print -u2 "Cask contains a forbidden command or Gatekeeper bypass"
    exit 2
fi

brew style "$CASK"

# Homebrew 6 audits Casks by token rather than arbitrary path. Create a disposable,
# uniquely named local tap so the strict audit exercises the same DSL loading path as users.
AUDIT_TAP="ihavealreadyseenit-audit-$$/casks"
if brew tap | grep -Fxq "$AUDIT_TAP"; then
    print -u2 "Refusing to reuse an existing audit tap: $AUDIT_TAP"
    exit 2
fi
brew tap-new --no-git "$AUDIT_TAP" >/dev/null
trap 'brew untap "$AUDIT_TAP" >/dev/null 2>&1 || true' EXIT
AUDIT_REPOSITORY="$(brew --repository "$AUDIT_TAP")"
mkdir -p "$AUDIT_REPOSITORY/Casks"
install -m 644 "$CASK" "$AUDIT_REPOSITORY/Casks/ihavealreadyseenit.rb"
brew audit --cask --strict "$AUDIT_TAP/ihavealreadyseenit"
print "Homebrew Cask audit passed: $CASK"
