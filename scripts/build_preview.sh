#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT_DIR/.build/current-preview}"
"$ROOT_DIR/scripts/build_app.sh"

APP_DIR="$APP_OUTPUT_DIR/Notepad.app"
PLIST="$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.eimg.notepad.preview' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Notepad Preview' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Notepad Preview' "$PLIST"
# Keep CFBundleDocumentTypes: Finder/Dock drops need the same file declarations
# as the installed app. The alternate handler rank leaves default apps alone.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Preview: $APP_DIR"
