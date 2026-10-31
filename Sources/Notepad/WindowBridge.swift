import AppKit
import Combine
import SwiftUI

/// Owns one real AppKit window per note. AppKit supplies tab drawing, close
/// buttons, dragging, and moving tabs between windows.
@MainActor
final class DocumentWindowCoordinator {
    private let editor: EditorViewModel
    private(set) var controllers: [UUID: DocumentWindowController] = [:]
    private var observation: AnyCancellable?
    private var selectedID: UUID?
    private var isSynchronizing = false

    init(editor: EditorViewModel) {
        self.editor = editor
        NSWindow.allowsAutomaticWindowTabbing = true
        observation = editor.objectWillChange.sink { [weak self] in
            // Published notifications arrive before their new values are stored.
            DispatchQueue.main.async { [weak self] in
                self?.synchronize()
            }
        }
    }

    func showCurrentDocument() {
        editor.showWindow()
        synchronize()
        controllers[editor.selectedDocumentID]?.window?.makeKeyAndOrderFront(nil)
    }

    func newDocument() {
        if editor.isWindowOpen {
            editor.newDocument()
        } else {
            editor.showWindow()
        }
        synchronize()
    }

    func synchronize() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        let openIDs = editor.isWindowOpen ? Set(editor.documents.map(\.id)) : []
        for id in Array(controllers.keys) where !openIDs.contains(id) {
            let controller = controllers.removeValue(forKey: id)
            controller?.window?.close()
        }
        guard editor.isWindowOpen else {
            selectedID = nil
            return
        }

        for document in editor.documents {
            if controllers[document.id] == nil {
                let parent = selectedID.flatMap { controllers[$0]?.window }
                    ?? controllers.values.first?.window
                let controller = DocumentWindowController(documentID: document.id, editor: editor, coordinator: self)
                controllers[document.id] = controller
                if let parent, let window = controller.window {
                    window.setFrame(parent.frame, display: false)
                    parent.addTabbedWindow(window, ordered: .above)
                }
            }
            controllers[document.id]?.update(document: document)
        }

        if selectedID != editor.selectedDocumentID {
            selectedID = editor.selectedDocumentID
            if NSApp.modalWindow == nil {
                controllers[editor.selectedDocumentID]?.window?.makeKeyAndOrderFront(nil)
            }
        }

        for controller in controllers.values {
            controller.updateTabControls()
        }
    }
}

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSUserInterfaceValidations, NSDraggingDestination {
    let documentID: UUID
    private let editor: EditorViewModel
    private weak var coordinator: DocumentWindowCoordinator?
    private let documentTitle = NSTextField(labelWithString: "")
    private var displayTitle = ""
    private var isDocumentDirty = false
    private var isTabBarUpdateScheduled = false

    static let newTabItem = NSToolbarItem.Identifier("notepad.newTab")
    static let titleItem = NSToolbarItem.Identifier("notepad.documentTitle")
    static let fontItem = NSToolbarItem.Identifier("notepad.fontSize")
    static let findItem = NSToolbarItem.Identifier("notepad.find")

    init(documentID: UUID, editor: EditorViewModel, coordinator: DocumentWindowCoordinator) {
        self.documentID = documentID
        self.editor = editor
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(documentID.uuidString)
        window.contentMinSize = NSSize(width: 500, height: 360)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.backgroundColor = .textBackgroundColor
        window.tabbingIdentifier = "notepad.documents"
        window.tabbingMode = .preferred
        window.delegate = self
        window.registerForDraggedTypes([.fileURL])
        let hostingController = NSHostingController(
            rootView: DocumentEditorView(documentID: documentID).environmentObject(editor)
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 880, height: 580))
        window.center()
        let toolbar = NSToolbar(identifier: "notepad.editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.titleItem]
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { return nil }

    func update(document: EditorDocumentState) {
        window?.title = document.displayTitle
        window?.tab.title = document.titleWithUnsavedIndicator
        window?.tab.toolTip = document.fileURL?.path ?? document.displayTitle
        window?.representedURL = document.fileURL
        window?.isDocumentEdited = document.isDirty
        displayTitle = document.displayTitle
        isDocumentDirty = document.isDirty
        updateDocumentTitle()
        let status = document.isDirty ? " — Unsaved changes" : ""
        documentTitle.toolTip = (document.fileURL?.path ?? document.displayTitle) + status
        window?.tab.toolTip = (document.fileURL?.path ?? document.displayTitle) + status
        window?.toolbar?.validateVisibleItems()
    }

    func updateTabControls() {
        guard let window else { return }
        let isSingleNote = (window.tabGroup?.windows.count ?? 1) == 1
        updateDocumentTitle()
        guard window.isVisible, window.tabGroup?.isTabBarVisible != !isSingleNote,
              !isTabBarUpdateScheduled else { return }
        isTabBarUpdateScheduled = true
        // Native presentation may update visibility later in the same run loop.
        // Coalesce callbacks so a second toggle cannot undo the first one.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.isTabBarUpdateScheduled = false
            let shouldShowTabs = (window.tabGroup?.windows.count ?? 1) > 1
            if window.isVisible, window.tabGroup?.isTabBarVisible != shouldShowTabs {
                window.toggleTabBar(nil)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Model changes close the corresponding native window on the next run
        // loop turn. Cancel/failed Save leave both the note and window intact.
        editor.closeDocument(id: documentID)
        return false
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSourceOperationMask.contains(.copy),
              !TextFileDrop.urls(from: sender.draggingPasteboard).isEmpty else { return [] }
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingEntered(sender) == .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender) else { return false }
        let urls = TextFileDrop.urls(from: sender.draggingPasteboard)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.editor.selectDocument(self.documentID)
            _ = self.editor.openDroppedFileURLs(urls)
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateTabControls()
        if editor.selectedDocumentID != documentID {
            editor.selectDocument(documentID)
        }
    }

    @objc private func addDocument(_ sender: Any?) {
        coordinator?.newDocument()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.newTabItem, .flexibleSpace, Self.titleItem, .flexibleSpace, Self.fontItem, .space, Self.findItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.titleItem {
            documentTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            documentTitle.textColor = .secondaryLabelColor
            documentTitle.alignment = .center
            documentTitle.lineBreakMode = .byTruncatingMiddle
            documentTitle.usesSingleLineMode = true
            documentTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            documentTitle.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                documentTitle.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
                documentTitle.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
            ])
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Document Title"
            item.isBordered = false
            item.view = documentTitle
            item.visibilityPriority = .high
            return item
        }
        if identifier == Self.fontItem {
            let group = NSToolbarItemGroup(
                itemIdentifier: identifier,
                images: ["textformat.size.smaller", "textformat.size.larger"].compactMap {
                    NSImage(systemSymbolName: $0, accessibilityDescription: nil)
                },
                selectionMode: .momentary,
                labels: ["Decrease Font Size", "Increase Font Size"],
                target: self,
                action: #selector(adjustFontSize(_:))
            )
            group.label = "Font Size"
            return group
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        if identifier == Self.newTabItem {
            item.label = "New Tab"
            item.toolTip = "New Tab (⌘T)"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
            item.isNavigational = true
            item.action = #selector(addDocument(_:))
        } else if identifier == Self.findItem {
            item.label = "Find"
            item.toolTip = "Find (⌘F)"
            item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
            item.action = #selector(find(_:))
        } else {
            return nil
        }
        return item
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(addDocument(_:)) {
            return editor.canCreateNewDocument
        }
        return true
    }

    @objc private func adjustFontSize(_ sender: NSToolbarItemGroup) {
        editor.adjustFontSize(by: sender.selectedIndex == 0 ? -1 : 1)
    }

    @objc private func find(_ sender: Any?) {
        editor.selectDocument(documentID)
        editor.showSearch(prefillFromSelection: true)
    }

    private func updateDocumentTitle() {
        let isSingleNote = (window?.tabGroup?.windows.count ?? 1) == 1
        let title = displayTitle + (isSingleNote && isDocumentDirty ? " •" : "")
        if documentTitle.stringValue != title {
            documentTitle.stringValue = title
        }
        documentTitle.setAccessibilityValue(title)
    }
}
