#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Notepad"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
DEST_APP="/Applications/$APP_NAME.app"
QUARANTINE_ROOT="$(mktemp -d /private/tmp/notepad-portability.XXXXXX)"
RENAMED_ROOT="$QUARANTINE_ROOT/repo-renamed"

cleanup() {
    if [[ -d "$RENAMED_ROOT" && ! -e "$ROOT_DIR" ]]; then
        mv "$RENAMED_ROOT" "$ROOT_DIR"
    fi
    rm -rf "$QUARANTINE_ROOT"
}
trap cleanup EXIT

"$SCRIPT_DIR/build_app.sh"

rm -rf "$DEST_APP"
ditto "$APP_DIR" "$DEST_APP"

echo "Checking copied app for external symlinks..."
if find "$DEST_APP" -type l -exec sh -c 'for path do target="$(readlink "$path")"; case "$target" in /*) case "$target" in "$0"/*) ;; *) echo "$path -> $target";; esac;; esac; done' "$DEST_APP" {} + | grep -q .; then
    find "$DEST_APP" -type l -ls
    echo "error: copied app contains symlinks that point outside the app bundle" >&2
    exit 1
fi

echo "Checking executable strings for repo/build paths..."
if strings "$DEST_APP/Contents/MacOS/"* | grep -E "/Users/|DerivedData|/\\.build/|$ROOT_DIR"; then
    echo "error: executable contains hard-coded local build paths" >&2
    exit 1
fi

echo "Checking Mach-O load commands for developer paths..."
if otool -l "$DEST_APP/Contents/MacOS/$APP_NAME" | grep -E "/Users/|DerivedData|/\\.build/|XcodeDefault\\.xctoolchain|$ROOT_DIR"; then
    echo "error: executable load commands contain local build or developer toolchain paths" >&2
    exit 1
fi

mkdir -p "$QUARANTINE_ROOT"
mv "$ROOT_DIR" "$RENAMED_ROOT"

echo "Launching copied app with original repo path unavailable..."
open -W -a "$DEST_APP" &
OPEN_PID=$!
sleep 5

if ! pgrep -x "$APP_NAME" >/dev/null; then
    echo "error: $APP_NAME did not stay running after launch" >&2
    wait "$OPEN_PID" || true
    exit 1
fi

osascript -e 'tell application id "com.eimg.notepad" to quit' >/dev/null 2>&1 || true
wait "$OPEN_PID" || true

echo "Portable app verification passed: $DEST_APP runs without $ROOT_DIR."
