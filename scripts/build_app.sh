#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Notepad"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="${APP_OUTPUT_DIR:-$ROOT_DIR/dist}/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/App/AppIcon.png"
APP_RESOURCES_SOURCE="$ROOT_DIR/Sources/Notepad/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_NAME="AppIcon.icns"
APP_VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/App/Info.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/App/Info.plist")}"
BUILD_ARCH="${BUILD_ARCH:-native}"

if [[ ! "$APP_VERSION" =~ '^[0-9]+(\.[0-9]+){0,2}$' || ! "$BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
    echo "error: APP_VERSION must have one to three numeric components; BUILD_NUMBER must be numeric" >&2
    exit 1
fi

MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
# The Swift Build backend in Swift 6.4 can write the deployment target into
# LC_BUILD_VERSION's SDK field, which opts the app into older macOS styling.
# Use SwiftPM's native backend so the linker records the selected SDK correctly.
BUILD_ARGS=(-c release --build-system native --sdk "$MACOS_SDK_PATH")
case "$BUILD_ARCH" in
    native|arm64|x86_64) BUILD_ARCHITECTURES=("$BUILD_ARCH") ;;
    universal) BUILD_ARCHITECTURES=(arm64 x86_64) ;;
    *) echo "error: BUILD_ARCH must be native, arm64, x86_64, or universal" >&2; exit 1 ;;
esac

cd "$ROOT_DIR"

BUILT_EXECUTABLES=()
for architecture in "${BUILD_ARCHITECTURES[@]}"; do
    ARCH_BUILD_ARGS=("${BUILD_ARGS[@]}")
    if [[ "$architecture" != native ]]; then
        ARCH_BUILD_ARGS+=(--arch "$architecture")
    fi
    swift build "${ARCH_BUILD_ARGS[@]}"
    ARCH_RELEASE_DIR="$(swift build --show-bin-path "${ARCH_BUILD_ARGS[@]}")"
    BUILT_EXECUTABLES+=("$ARCH_RELEASE_DIR/$APP_NAME")
done

if [[ "$BUILD_ARCH" == universal ]]; then
    # Passing both --arch flags to SwiftPM switches back to Swift Build, even
    # with --build-system native. Combine two correctly linked native builds.
    RELEASE_DIR="$BUILD_DIR/universal-release"
    mkdir -p "$RELEASE_DIR"
    lipo -create "${BUILT_EXECUTABLES[@]}" -output "$RELEASE_DIR/$APP_NAME"
else
    RELEASE_DIR="$ARCH_RELEASE_DIR"
fi

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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
cp "$RELEASE_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Check every architecture before signing so a future toolchain change cannot
# silently ship a compatibility-styled UI again.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
LINKED_SDK_VERSIONS="$(otool -l "$MACOS_DIR/$APP_NAME" | awk '$1 == "sdk" {print $2}')"
if [[ -z "$LINKED_SDK_VERSIONS" ]]; then
    echo "error: executable has no linked SDK version" >&2
    exit 1
fi
while IFS= read -r linked_sdk; do
    if [[ "${linked_sdk%%.*}" != "${SDK_VERSION%%.*}" ]]; then
        echo "error: linked SDK $linked_sdk differs from selected SDK $SDK_VERSION; this changes native macOS styling" >&2
        exit 1
    fi
done <<< "$LINKED_SDK_VERSIONS"

ditto "$APP_RESOURCES_SOURCE" "$RESOURCES_DIR"
find "$RESOURCES_DIR" -name ".DS_Store" -delete

while IFS= read -r rpath; do
    case "$rpath" in
        /Applications/Xcode.app/*|*Toolchains/XcodeDefault.xctoolchain*)
            install_name_tool -delete_rpath "$rpath" "$MACOS_DIR/$APP_NAME"
            ;;
    esac
done < <(otool -l "$MACOS_DIR/$APP_NAME" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | sort -u)

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
    codesign --verify --deep --strict "$APP_DIR"
fi

echo "Built $APP_DIR"
