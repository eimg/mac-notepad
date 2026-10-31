# mac-notepad

`mac-notepad` is a small native macOS plain-text editor built with SwiftUI and a lightweight web-based editor surface.

It keeps the app intentionally simple: plain text only, manual save/open, lightweight tabs, adjustable font and line height, word wrap, and a minimal Mac-style UI.

![mac-notepad screenshot](Screenshot.png)

## Features

- Native macOS app with a standalone `.app` bundle build script
- Plain-text editing with no rich text, preview, sidebar, or autosave
- Native macOS document tabs, with an individual close control on each tab
- Centered active-document title; one fixed New Tab button on the left, with ⌘T / ⌘W shortcuts
- Numbered new notes; closing the last tab closes the window after checking unsaved changes
- Adjustable font, font size, line height, and word wrap
- Inline Find bar with match counts, highlights, and an expandable Replace row
- Unsaved-change dots on modified tabs, or beside the title when a single note is open
- Drag-and-drop `.txt` opening on the editor, window, or app icon; multiple files and duplicate-file selection are supported
- Built-in Myanmar font options for Burmese text
- `.txt` file association support for Finder and `Open With`

## Build

Requires macOS and Xcode with Swift 6.3 or later.

```bash
swift test
./scripts/build_app.sh
open dist/Notepad.app
```

To build a separate preview without replacing the installed app, run:

```bash
./scripts/build_preview.sh
open .build/current-preview/Notepad.app
```

Previews use a separate app identity and a single stable output folder. Their file-type declarations are retained so Finder and Dock file drops work.

To verify the app is portable after copying to `/Applications`, run:

```bash
./scripts/verify_portable_app.sh
```

## DMG Installer

Download an installer from [GitHub Releases](https://github.com/eimg/mac-notepad/releases), open the DMG, and drag `Notepad.app` onto `Applications`. Eject the disk image and open Notepad from Applications. Requires macOS 13 or later.

To build an installer locally for both Apple silicon and Intel Macs:

```bash
./scripts/build_dmg.sh
```

This creates `dist/Notepad-1.1.0-universal.dmg` and a `.sha256` checksum file. The script verifies the disk image, bundled resources, app signature, version, and both executable architectures before producing the checksum. Generated installers are ignored by Git; the existing `dist/Notepad.app` is kept intact.

For a smaller installer targeting one architecture, set `BUILD_ARCH=arm64` or `BUILD_ARCH=x86_64`. Without `APP_VERSION` and `BUILD_NUMBER`, the scripts use the values in `App/Info.plist`. `build_app.sh` also accepts these settings and defaults to building for the current Mac.

These builds use ad-hoc signing and are **not notarized by Apple**. macOS may block a downloaded copy on first launch. If you trust its source, attempt to open it, then go to **System Settings → Privacy & Security → Open Anyway**. Developer ID signing and notarization require an Apple Developer account and are not configured in this workflow.

Verify a downloaded checksum from the folder containing both files:

```bash
shasum -a 256 -c Notepad-1.1.0-universal.dmg.sha256
```

## Releases

The [release workflow](.github/workflows/release.yml) runs tests, builds and verifies a universal DMG, and publishes it with its checksum and generated release notes when a `vMAJOR.MINOR.PATCH` tag is pushed. Commit and push the workflow and packaging scripts before creating the first release tag:

```bash
git tag -a v1.0.0 -m "Notepad 1.0.0"
git push origin v1.0.0
```

Use a new version tag for each release. The tag sets the bundled app version; the Actions run number sets its build number. The workflow uses the repository's built-in `GITHUB_TOKEN` with `contents: write`; no release token secret is needed.

To test packaging without publishing, open **Actions → Release → Run workflow**, enter a numeric version such as `1.0.0`, and download the installer from the run's artifacts.

## Run the bundled app

The repository includes the current production app at `dist/Notepad.app`, with the same Notepad identity used by the installed app.

After cloning the repo:

```bash
open dist/Notepad.app
```

## Tech

- Swift Package Manager
- SwiftUI for the editor host and inline Find/Replace bar
- `WKWebView` + CodeMirror for the editing surface
- AppKit for document windows, native tabs, toolbar, menus, and file integration

## Improvement passes

The current pass uses one AppKit window per note, grouped into the system document tab strip. Each tab has its own close control, and each note keeps its editor instance when switching tabs. The active document title is centered in the title row, with font size and Find on the right. The tab strip stays hidden for a single note. New Tab stays on the left of the title row at all times; the native tab-strip add button is omitted. Modified notes show a dot beside their tab name, or beside the centered title when only one note is open. Saving or returning to the saved contents clears the dot; empty new notes stay unmarked. The window has no custom tab drawing or inset editor border. Untitled notes have stable numbers. Closing still offers Save, Cancel, and Don't Save; Cancel and failed saves keep the note open. Reopening after the last window closes starts with one fresh note.

Find now appears in a compact bar above the editor. It shows match counts and highlights, wraps in both directions, and keeps input focus while navigating results. Replace expands into a second row (also available with ⌥⌘F); Replace All is one undoable edit. Esc or the close button dismisses the bar and returns focus to the editor. Closing the bar retains its query.

The app build script selects the active macOS SDK explicitly and uses SwiftPM's native build backend. On this computer, Swift 6.4's default Swift Build backend recorded SDK 13.0 in the executable even when compiling against SDK 27.0; that caused macOS to apply older compatibility styling. Packaging now checks the linked SDK major version in every architecture before signing. The deployment target remains macOS 13.

Next passes, in suggested order:

1. Add local draft recovery, session restoration, and reopening closed tabs while retaining manual saving of original files.
2. Retain independent search queries between tabs and verify Burmese keyboard composition in the Find/Replace fields. Burmese matching, multiline queries, literal punctuation, and replacement/undo have real-editor regression coverage.
3. Replace or explain the five-tab limit, and detect external file changes before overwriting a file.
4. Establish Burmese editing regressions for composition, combining marks, deletion, selection, undo, and tab switching; measure large-note performance and improve the JavaScript/Swift bridge where needed.
