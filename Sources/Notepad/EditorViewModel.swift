import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    static let shared = EditorViewModel()
    static let maxDocumentCount = 5

    @Published private(set) var documents = [EditorDocumentState()]
    @Published private(set) var selectedDocumentID: UUID
    @Published private(set) var preferences: EditorPreferences
    @Published private(set) var searchPanel = SearchPanelState()
    @Published private(set) var searchCommandNonce = 0
    @Published private(set) var searchCommand: SearchCommand?
    @Published var isSearchPopoverPresented = false

    private let defaults: UserDefaults
    private weak var trackedWindow: NSWindow?

    private enum DefaultsKey {
        static let fontName = "editor.fontName"
        static let fontSize = "editor.fontSize"
        static let lineHeightMultiple = "editor.lineHeightMultiple"
        static let wordWrap = "editor.wordWrap"
    }

    init(defaults: UserDefaults = .standard) {
        let initialDocument = EditorDocumentState()
        self.defaults = defaults
        self.documents = [initialDocument]
        self.selectedDocumentID = initialDocument.id
        self.preferences = EditorViewModel.loadPreferences(from: defaults)
    }

    var canSave: Bool {
        currentDocument.fileURL != nil || !currentDocument.text.isEmpty
    }

    var canCreateNewDocument: Bool {
        documents.count < Self.maxDocumentCount
    }

    var selectedTabIndex: Int {
        documents.firstIndex(where: { $0.id == selectedDocumentID }) ?? 0
    }

    var currentDocument: EditorDocumentState {
        get { documents[selectedTabIndex] }
        set { documents[selectedTabIndex] = newValue }
    }

    func document(id: UUID) -> EditorDocumentState? {
        documents.first { $0.id == id }
    }

    func text(for documentID: UUID) -> String {
        document(id: documentID)?.text ?? ""
    }

    func attachWindow(_ window: NSWindow) {
        trackedWindow = window
        window.delegate = WindowDelegate.shared
        updateWindowState()
    }

    func updateText(_ text: String) {
        guard currentDocument.text != text else { return }
        currentDocument.text = text
        updateWindowState()
    }

    func updateText(_ text: String, for documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        guard documents[index].text != text else { return }
        documents[index].text = text
        updateWindowState()
    }

    func selectDocument(_ id: UUID) {
        guard documents.contains(where: { $0.id == id }) else { return }
        if selectedDocumentID != id {
            hideSearch(reset: true)
        }
        selectedDocumentID = id
        updateWindowState()
    }

    func setFontName(_ fontName: String) {
        preferences.fontName = fontName
        persistPreferences()
    }

    func setWordWrap(_ enabled: Bool) {
        preferences.wordWrap = enabled
        persistPreferences()
    }

    func adjustFontSize(by delta: Double) {
        let newSize = min(max(preferences.fontSize + delta, 10), 36)
        guard newSize != preferences.fontSize else { return }
        preferences.fontSize = newSize
        persistPreferences()
    }

    func adjustLineHeight(by delta: Double) {
        let newValue = min(max(preferences.lineHeightMultiple + delta, 1.5), 3.5)
        guard newValue != preferences.lineHeightMultiple else { return }
        preferences.lineHeightMultiple = (newValue * 100).rounded() / 100
        persistPreferences()
    }

    func resetFormatting() {
        preferences = .default
        persistPreferences()
    }

    func showSearch(prefillFromSelection: Bool = false) {
        searchPanel.isVisible = true
        isSearchPopoverPresented = true
        if prefillFromSelection {
            issueSearchCommand(.useSelectionForFind)
        }
    }

    func toggleSearch(prefillFromSelection: Bool = false) {
        if searchPanel.isVisible {
            hideSearch(reset: false)
        } else {
            showSearch(prefillFromSelection: prefillFromSelection)
        }
    }

    func hideSearch(reset: Bool = false) {
        searchPanel.isVisible = false
        isSearchPopoverPresented = false
        if reset {
            searchPanel.query = ""
            searchPanel.replacement = ""
        }
    }

    func setSearchQuery(_ value: String) {
        searchPanel.query = value
    }

    func useSelectionForSearch(_ value: String) {
        guard !value.isEmpty else { return }
        searchPanel.query = value
    }

    func setReplacementText(_ value: String) {
        searchPanel.replacement = value
    }

    func findNext() {
        issueSearchCommand(.findNext)
    }

    func findPrevious() {
        issueSearchCommand(.findPrevious)
    }

    func replaceCurrent() {
        issueSearchCommand(.replaceCurrent)
    }

    func replaceAll() {
        issueSearchCommand(.replaceAll)
    }

    func newDocument() {
        guard canCreateNewDocument else {
            NSSound.beep()
            return
        }

        hideSearch(reset: true)
        let newDocument = EditorDocumentState()
        documents.append(newDocument)
        selectedDocumentID = newDocument.id
        updateWindowState()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(at: url)
    }

    func openDocument(at url: URL) {
        do {
            let standardizedURL = url.standardizedFileURL
            if selectOpenDocument(at: standardizedURL) {
                return
            }

            let contents = try Self.readPlainText(from: url)
            let openedDocument = EditorDocumentState(fileURL: standardizedURL, text: contents, savedText: contents)
            if shouldReuseInitialDocument {
                documents[0] = openedDocument
                selectedDocumentID = openedDocument.id
            } else {
                documents.append(openedDocument)
                selectedDocumentID = openedDocument.id
            }
            updateWindowState()
        } catch {
            presentError(message: "Could not open \(url.lastPathComponent).\n\(error.localizedDescription)")
        }
    }

    func openDocuments(at urls: [URL]) {
        for url in urls {
            openDocument(at: url)
        }
    }

    func openDroppedItems(from providers: [NSItemProvider]) -> Bool {
        let fileURLType = UTType.fileURL.identifier
        let matchingProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(fileURLType) }
        guard !matchingProviders.isEmpty else { return false }

        for provider in matchingProviders {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "txt"
                else { return }

                DispatchQueue.main.async {
                    self.openDocument(at: url)
                }
            }
        }

        return true
    }

    @discardableResult
    func saveDocument() -> Bool {
        if let fileURL = currentDocument.fileURL {
            return writeDocument(to: fileURL)
        }
        return saveDocumentAs()
    }

    @discardableResult
    func saveDocumentAs() -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = currentDocument.fileURL?.lastPathComponent ?? "Untitled.txt"

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeDocument(to: url)
    }

    func confirmTermination() -> NSApplication.TerminateReply {
        for documentID in documents.map(\.id) {
            selectedDocumentID = documentID
            guard confirmIfNeeded(action: "quit") else {
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    func confirmClose(window: NSWindow) -> Bool {
        trackedWindow = window
        let shouldClose = confirmIfNeeded(action: "close this window")
        if shouldClose {
            resetAfterWindowClose()
        }
        return shouldClose
    }

    func closeCurrentTab() {
        closeDocument(id: selectedDocumentID)
    }

    func closeDocument(id: UUID) {
        guard documents.count > 1 else { return }
        guard let closingIndex = documents.firstIndex(where: { $0.id == id }) else { return }

        let previousSelection = selectedDocumentID
        selectedDocumentID = id
        guard confirmIfNeeded(action: "close this tab") else {
            selectedDocumentID = previousSelection
            updateWindowState()
            return
        }

        documents.remove(at: closingIndex)

        if selectedDocumentID == id {
            let fallbackIndex = min(closingIndex, documents.count - 1)
            selectedDocumentID = documents[fallbackIndex].id
        }

        updateWindowState()
    }

    func resetAfterWindowClose() {
        let document = EditorDocumentState()
        documents = [document]
        selectedDocumentID = document.id
        updateWindowState()
    }

    private func writeDocument(to url: URL) -> Bool {
        do {
            try currentDocument.text.write(to: url, atomically: true, encoding: .utf8)
            currentDocument.fileURL = url
            currentDocument.savedText = currentDocument.text
            updateWindowState()
            return true
        } catch {
            presentError(message: "Could not save the document.\n\(error.localizedDescription)")
            return false
        }
    }

    private func confirmIfNeeded(action: String) -> Bool {
        guard currentDocument.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \(currentDocument.displayTitle)?"
        alert.informativeText = "Your changes will be lost if you don’t save them before you \(action)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveDocument()
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    private func presentError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Notepad Error"
        alert.informativeText = message
        alert.runModal()
    }

    private func updateWindowState() {
        trackedWindow?.title = "Notepad"
        trackedWindow?.representedURL = currentDocument.fileURL
        trackedWindow?.isDocumentEdited = currentDocument.isDirty
    }

    private func persistPreferences() {
        defaults.set(preferences.fontName, forKey: DefaultsKey.fontName)
        defaults.set(preferences.fontSize, forKey: DefaultsKey.fontSize)
        defaults.set(preferences.lineHeightMultiple, forKey: DefaultsKey.lineHeightMultiple)
        defaults.set(preferences.wordWrap, forKey: DefaultsKey.wordWrap)
    }

    private func issueSearchCommand(_ command: SearchCommand) {
        searchCommand = command
        searchCommandNonce += 1
    }

    private var shouldReuseInitialDocument: Bool {
        documents.count == 1 &&
        currentDocument.fileURL == nil &&
        currentDocument.text.isEmpty &&
        !currentDocument.isDirty
    }

    private func selectOpenDocument(at url: URL) -> Bool {
        guard let document = documents.first(where: { $0.fileURL?.standardizedFileURL == url }) else {
            return false
        }

        selectedDocumentID = document.id
        updateWindowState()
        return true
    }

    private static func loadPreferences(from defaults: UserDefaults) -> EditorPreferences {
        let fontName = defaults.string(forKey: DefaultsKey.fontName) ?? EditorPreferences.default.fontName
        let fontSize = defaults.object(forKey: DefaultsKey.fontSize) as? Double ?? EditorPreferences.default.fontSize
        let lineHeightMultiple = defaults.object(forKey: DefaultsKey.lineHeightMultiple) as? Double ?? EditorPreferences.default.lineHeightMultiple
        let hasWrapValue = defaults.object(forKey: DefaultsKey.wordWrap) != nil
        let wordWrap = hasWrapValue ? defaults.bool(forKey: DefaultsKey.wordWrap) : EditorPreferences.default.wordWrap

        return EditorPreferences(
            fontName: fontName,
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple,
            wordWrap: wordWrap
        )
    }

    nonisolated static func readPlainText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let utf8Text = String(data: data, encoding: .utf8) {
            return utf8Text
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
