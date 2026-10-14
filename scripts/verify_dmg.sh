#!/bin/zsh

set -euo pipefail

if (( $# != 3 )); then
    echo "Usage: $0 <dmg-path> <expected-version> <native|arm64|x86_64|universal>" >&2
    exit 1
fi

DMG_PATH="$1"
EXPECTED_VERSION="$2"
EXPECTED_ARCH="$3"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notepad-dmg-check.XXXXXX")"
MOUNTED=0
cleanup() {
    if (( MOUNTED )); then
        hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
    fi
    rmdir "$MOUNT_DIR"
}
trap cleanup EXIT

hdiutil verify "$DMG_PATH"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_DIR" -quiet
MOUNTED=1

APP_DIR="$MOUNT_DIR/Notepad.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/Notepad"
[[ -x "$EXECUTABLE" && -f "$MOUNT_DIR/Install.txt" ]]
[[ "$(readlink "$MOUNT_DIR/Applications")" == /Applications ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" == "$EXPECTED_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist")" == 13.0 ]]
for resource in AppIcon.icns editor.html codemirror/lib/codemirror.min.js codemirror/lib/codemirror.min.css codemirror/addon/display/placeholder.min.js codemirror/addon/search/searchcursor.js; do
    [[ -s "$APP_DIR/Contents/Resources/$resource" ]]
done

case "$EXPECTED_ARCH" in
    universal) EXPECTED_ARCHES=(arm64 x86_64) ;;
    arm64|x86_64) EXPECTED_ARCHES=("$EXPECTED_ARCH") ;;
    native) EXPECTED_ARCHES=("$(uname -m)") ;;
    *) echo "error: unknown architecture $EXPECTED_ARCH" >&2; exit 1 ;;
esac
for arch in "${EXPECTED_ARCHES[@]}"; do
    lipo "$EXECUTABLE" -verify_arch "$arch"
done
[[ "$(otool -l "$EXECUTABLE" | awk '$1 == "minos" {print $2}' | sort -u)" == 13.0 ]]
codesign --verify --deep --strict "$APP_DIR"
echo "DMG verification passed: version $EXPECTED_VERSION, architecture $EXPECTED_ARCH."
