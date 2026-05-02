#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Notepad"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/App/AppIcon.png"
APP_RESOURCES_SOURCE="$ROOT_DIR/Sources/Notepad/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_NAME="AppIcon.icns"

cd "$ROOT_DIR"

swift build -c release
RELEASE_DIR="$(swift build --show-bin-path -c release)"

rm -rf "$APP_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_NAME"

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$RELEASE_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
ditto "$APP_RESOURCES_SOURCE" "$RESOURCES_DIR"
find "$RESOURCES_DIR" -name ".DS_Store" -delete

while IFS= read -r rpath; do
    case "$rpath" in
        /Applications/Xcode.app/*|*Toolchains/XcodeDefault.xctoolchain*)
            install_name_tool -delete_rpath "$rpath" "$MACOS_DIR/$APP_NAME"
            ;;
    esac
done < <(otool -l "$MACOS_DIR/$APP_NAME" | awk '/cmd LC_RPATH/{getline; getline; print $2}')

if find "$APP_DIR" -type l -exec test ! -e {} \; -print -quit | grep -q .; then
    echo "error: bundle contains a broken symlink" >&2
    find "$APP_DIR" -type l -ls >&2
    exit 1
fi

if find "$APP_DIR" -type l -exec sh -c 'for path do target="$(readlink "$path")"; case "$target" in /*) case "$target" in "$0"/*) ;; *) echo "$path -> $target";; esac;; esac; done' "$APP_DIR" {} + | grep -q .; then
    echo "error: bundle contains symlinks that point outside the app bundle" >&2
    find "$APP_DIR" -type l -ls >&2
    exit 1
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "Built $APP_DIR"
