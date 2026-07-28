#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
swift test --enable-code-coverage
BIN_DIR="$(swift build --show-bin-path)"
PROFILE_DIR="$BIN_DIR/codecov"
RAW_PROFILE="$PROFILE_DIR/ihavealreadyseenit-tests.profraw"
PROFILE="$PROFILE_DIR/ihavealreadyseenit-tests.profdata"
mkdir -p "$PROFILE_DIR"
rm -f "$RAW_PROFILE" "$PROFILE"
LLVM_PROFILE_FILE="$RAW_PROFILE" "$BIN_DIR/ihavealreadyseenit-tests"
xcrun llvm-profdata merge -sparse "$RAW_PROFILE" -o "$PROFILE"
REPORT="$(xcrun llvm-cov report "$BIN_DIR/ihavealreadyseenit-tests" \
    -instr-profile="$PROFILE" \
    -ignore-filename-regex='Tests/|resource_bundle_accessor.swift')"
print "$REPORT"
print "$REPORT" | awk '/^TOTAL/ { if (($10 + 0) < 80) exit 1 }'
