# mac-notepad

`mac-notepad` is a small native macOS plain-text editor built with SwiftUI and AppKit.

It keeps the app intentionally simple: plain text only, manual save/open, lightweight tabs, adjustable font and line height, word wrap, and a minimal Mac-style UI.

![mac-notepad screenshot](Screenshot.png)

## Features

- Native macOS app with a standalone `.app` bundle build script
- Plain-text editing with no rich text, preview, sidebar, or autosave
- Multiple tabs in one window
- Adjustable font, font size, line height, and word wrap
- Built-in Myanmar font options for Burmese text
- `.txt` file association support for Finder and `Open With`

## Build

```bash
swift test
./scripts/build_app.sh
open dist/Notepad.app
```

## Tech

- Swift Package Manager
- SwiftUI for app structure and tab UI
- AppKit `NSTextView` for native macOS text editing behavior
