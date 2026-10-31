import AppKit

@MainActor
final class NotepadMenuController: NSObject, NSMenuItemValidation, NSMenuDelegate {
    private let editor: EditorViewModel
    private let windows: DocumentWindowCoordinator

    init(editor: EditorViewModel, windows: DocumentWindowCoordinator) {
        self.editor = editor
        self.windows = windows
    }

    func install() {
        let bar = NSMenu()
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Notepad"
        let app = submenu(name, in: bar)
        item("About \(name)", in: app, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        let services = submenu("Services", in: app)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        item("Hide \(name)", in: app, action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp)
        item("Hide Others", in: app, action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: NSApp)
        item("Show All", in: app, action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        app.addItem(.separator())
        item("Quit \(name)", in: app, action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)

        let file = submenu("File", in: bar)
        item("New", in: file, action: #selector(newDocument(_:)), key: "n")
        item("New Tab", in: file, action: #selector(newDocument(_:)), key: "t")
        item("Open…", in: file, action: #selector(openDocument(_:)), key: "o")
        file.addItem(.separator())
        item("Close Tab", in: file, action: #selector(closeTab(_:)), key: "w")
        item("Save", in: file, action: #selector(save(_:)), key: "s")
        item("Save As…", in: file, action: #selector(saveAs(_:)), key: "s", modifiers: [.command, .shift])

        let edit = submenu("Edit", in: bar)
        responderItem("Undo", in: edit, action: Selector(("undo:")), key: "z")
        responderItem("Redo", in: edit, action: Selector(("redo:")), key: "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        responderItem("Cut", in: edit, action: #selector(NSText.cut(_:)), key: "x")
        responderItem("Copy", in: edit, action: #selector(NSText.copy(_:)), key: "c")
        responderItem("Paste", in: edit, action: #selector(NSText.paste(_:)), key: "v")
        responderItem("Select All", in: edit, action: #selector(NSText.selectAll(_:)), key: "a")
        edit.addItem(.separator())
        item("Find", in: edit, action: #selector(find(_:)), key: "f")
        item("Find Next", in: edit, action: #selector(findNext(_:)), key: "g")
        item("Find Previous", in: edit, action: #selector(findPrevious(_:)), key: "g", modifiers: [.command, .shift])
        item("Replace", in: edit, action: #selector(showReplace(_:)), key: "f", modifiers: [.command, .option])

        let format = submenu("Format", in: bar)
        let fonts = submenu("Font", in: format)
        for name in EditorPreferences.availableFonts {
            let entry = item(name, in: fonts, action: #selector(setFont(_:)))
            entry.representedObject = name
        }
        format.addItem(.separator())
        item("Increase Font Size", in: format, action: #selector(increaseFont(_:)), key: "+")
        item("Decrease Font Size", in: format, action: #selector(decreaseFont(_:)), key: "-")
        format.addItem(.separator())
        item("Increase Line Height", in: format, action: #selector(increaseLineHeight(_:)), key: "]", modifiers: [.command, .option])
        item("Decrease Line Height", in: format, action: #selector(decreaseLineHeight(_:)), key: "[", modifiers: [.command, .option])
        format.addItem(.separator())
        item("Reset Formatting", in: format, action: #selector(resetFormatting(_:)))
        format.addItem(.separator())
        item("Word Wrap", in: format, action: #selector(toggleWrap(_:)))

        let view = submenu("View", in: bar)
        responderItem("Enter Full Screen", in: view, action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control])
        let window = submenu("Window", in: bar)
        responderItem("Minimize", in: window, action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
        responderItem("Zoom", in: window, action: #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        responderItem("Show Next Tab", in: window, action: #selector(NSWindow.selectNextTab(_:)), key: "\t", modifiers: [.control])
        responderItem("Show Previous Tab", in: window, action: #selector(NSWindow.selectPreviousTab(_:)), key: "\t", modifiers: [.control, .shift])
        responderItem("Move Tab to New Window", in: window, action: #selector(NSWindow.moveTabToNewWindow(_:)))
        responderItem("Merge All Windows", in: window, action: #selector(NSWindow.mergeAllWindows(_:)))
        window.addItem(.separator())
        item("Bring All to Front", in: window, action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
        NSApp.windowsMenu = window
        NSApp.helpMenu = submenu("Help", in: bar)
        NSApp.mainMenu = bar
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let child = NSMenu(title: title)
        child.delegate = self
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = child
        menu.addItem(entry)
        return child
    }

    @discardableResult
    private func item(_ title: String, in menu: NSMenu, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = target ?? self
        menu.addItem(entry)
        return entry
    }

    private func responderItem(_ title: String, in menu: NSMenu, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) {
        let entry = item(title, in: menu, action: action, key: key, modifiers: modifiers)
        entry.target = nil
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(newDocument(_:)): return editor.canCreateNewDocument
        case #selector(closeTab(_:)), #selector(saveAs(_:)): return editor.isWindowOpen
        case #selector(save(_:)): return editor.isWindowOpen && editor.canSave
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return editor.isWindowOpen && !editor.searchPanel.query.isEmpty
        default: return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(setFont(_:)) {
                item.state = (item.representedObject as? String) == editor.preferences.fontName ? .on : .off
            } else if item.action == #selector(toggleWrap(_:)) {
                item.state = editor.preferences.wordWrap ? .on : .off
            }
        }
    }

    @objc private func newDocument(_ sender: Any?) { windows.newDocument() }
    @objc private func openDocument(_ sender: Any?) { editor.openDocument() }
    @objc private func closeTab(_ sender: Any?) { editor.closeCurrentTab() }
    @objc private func save(_ sender: Any?) { _ = editor.saveDocument() }
    @objc private func saveAs(_ sender: Any?) { _ = editor.saveDocumentAs() }
    @objc private func find(_ sender: Any?) {
        windows.showCurrentDocument()
        editor.showSearch(prefillFromSelection: true)
    }
    @objc private func showReplace(_ sender: Any?) {
        windows.showCurrentDocument()
        editor.showSearch(prefillFromSelection: true, replacing: true)
    }
    @objc private func findNext(_ sender: Any?) { editor.findNext() }
    @objc private func findPrevious(_ sender: Any?) { editor.findPrevious() }
    @objc private func setFont(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { editor.setFontName(name) }
    }
    @objc private func increaseFont(_ sender: Any?) { editor.adjustFontSize(by: 1) }
    @objc private func decreaseFont(_ sender: Any?) { editor.adjustFontSize(by: -1) }
    @objc private func increaseLineHeight(_ sender: Any?) { editor.adjustLineHeight(by: 0.04) }
    @objc private func decreaseLineHeight(_ sender: Any?) { editor.adjustLineHeight(by: -0.04) }
    @objc private func resetFormatting(_ sender: Any?) { editor.resetFormatting() }
    @objc private func toggleWrap(_ sender: Any?) { editor.setWordWrap(!editor.preferences.wordWrap) }
}
