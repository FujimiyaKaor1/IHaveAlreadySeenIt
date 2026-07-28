#!/bin/zsh
set -euo pipefail

APP="${1:?Usage: scripts/test-app-launch.sh /path/to/IHaveAlreadySeenIt.app}"
EXECUTABLE="$APP/Contents/MacOS/IHaveAlreadySeenItApp"
RESOURCES="$APP/Contents/Resources"
APP_BUNDLE="$RESOURCES/IHaveAlreadySeenIt_IHaveAlreadySeenItApp.bundle"

if [[ ! -x "$EXECUTABLE" || ! -d "$APP_BUNDLE" ]]; then
    print -u2 "Packaged GUI executable or resource bundle is missing"
    exit 2
fi

"$EXECUTABLE" >/dev/null 2>&1 &
PID=$!

cleanup() {
    if kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

for _ in {1..15}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        wait "$PID" 2>/dev/null || true
        print -u2 "Packaged GUI exited during startup"
        exit 1
    fi
    sleep 1
done

print "Packaged GUI startup smoke test passed"
