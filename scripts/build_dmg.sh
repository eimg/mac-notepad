#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export APP_VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/App/Info.plist")}"
export BUILD_ARCH="${BUILD_ARCH:-universal}"
export APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT_DIR/.build/dmg-app}"
DMG_OUTPUT_DIR="${DMG_OUTPUT_DIR:-$ROOT_DIR/dist}"

"$ROOT_DIR/scripts/build_app.sh"

mkdir -p "$DMG_OUTPUT_DIR"
DMG_OUTPUT_DIR="$(cd "$DMG_OUTPUT_DIR" && pwd)"
DMG_NAME="Notepad-$APP_VERSION-$BUILD_ARCH.dmg"
DMG_PATH="$DMG_OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notepad-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_OUTPUT_DIR/Notepad.app" "$STAGING_DIR/Notepad.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/Install.txt" <<'EOF'
Notepad for macOS 13 or later

Drag Notepad.app onto Applications, then eject this disk image.
Open Notepad from your Applications folder.

This build is ad-hoc signed and is not notarized by Apple. If macOS
blocks it, use System Settings > Privacy & Security > Open Anyway
after attempting to open the app, if you trust its source.
EOF

hdiutil create -volname "Notepad $APP_VERSION" -srcfolder "$STAGING_DIR" \
    -fs HFS+ -format UDZO -ov "$DMG_PATH"
"$ROOT_DIR/scripts/verify_dmg.sh" "$DMG_PATH" "$APP_VERSION" "$BUILD_ARCH"

(cd "$DMG_OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "Built $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
