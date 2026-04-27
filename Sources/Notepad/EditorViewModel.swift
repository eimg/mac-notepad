import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    static let shared = EditorViewModel()
    static let maxDocumentCount = 5
    private static let fontSizeRange = 10.0...36.0
    private static let lineHeightRange = 1.5...3.5

    @Published private(set) var documents = [EditorDocumentState()]
    @Published private(set) var selectedDocumentID: UUID
    @Published private(set) var preferences: EditorPreferences
    @Published private(set) var searchPanel = SearchPanelState()
    @Published private(set) var searchCommandNonce = 0
    @Published private(set) var searchCommand: SearchCommand?
    @Published var isSearchPopoverPresented = false

    private let defaults: UserDefaults
    private let unsavedChangesDecision: (EditorDocumentState, String) -> UnsavedChangesDecision
    private let errorPresenter: (String) -> Void
    private let warningPresenter: (String, String) -> Void
    private weak var trackedWindow: NSWindow?

    enum UnsavedChangesDecision {
        case save
        case discard
        case cancel
    }

    private enum DefaultsKey {
        static let fontName = "editor.fontName"
        static let fontSize = "editor.fontSize"
        static let lineHeightMultiple = "editor.lineHeightMultiple"
        static let wordWrap = "editor.wordWrap"
    }

    init(
        defaults: UserDefaults = .standard,
        unsavedChangesDecision: ((EditorDocumentState, String) -> UnsavedChangesDecision)? = nil,
        errorPresenter: ((String) -> Void)? = nil,
        warningPresenter: ((String, String) -> Void)? = nil
    ) {
        let initialDocument = EditorDocumentState()
        self.defaults = defaults
        self.unsavedChangesDecision = unsavedChangesDecision ?? Self.presentUnsavedChangesAlert
        self.errorPresenter = errorPresenter ?? Self.presentErrorAlert
        self.warningPresenter = warningPresenter ?? Self.presentWarningAlert
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
        let newSize = Self.clamp(preferences.fontSize + delta, to: Self.fontSizeRange)
        guard newSize != preferences.fontSize else { return }
        preferences.fontSize = newSize
        persistPreferences()
    }

    func adjustLineHeight(by delta: Double) {
        let newValue = Self.clamp(preferences.lineHeightMultiple + delta, to: Self.lineHeightRange)
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
                guard canCreateNewDocument else {
                    NSSound.beep()
                    return
                }

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
        return saveCurrentDocument(to: url)
    }

    @discardableResult
    func saveCurrentDocument(to url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let isOpenInAnotherTab = documents.contains { document in
            document.id != currentDocument.id &&
            document.fileURL?.standardizedFileURL == standardizedURL
        }
        if isOpenInAnotherTab {
            presentWarning(
                title: "File Already Open",
                message: "\(standardizedURL.lastPathComponent) is already open in another tab. Close that tab before saving this note to the same file."
            )
            return false
        }

        return writeDocument(to: standardizedURL)
    }

    func confirmTermination() -> NSApplication.TerminateReply {
        confirmAllIfNeeded(action: "quit") ? .terminateNow : .terminateCancel
    }

    func confirmClose(window: NSWindow) -> Bool {
        trackedWindow = window
        let shouldClose = confirmAllIfNeeded(action: "close this window")
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
            currentDocument.fileURL = url.standardizedFileURL
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

        switch unsavedChangesDecision(currentDocument, action) {
        case .save:
            return saveDocument()
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func confirmAllIfNeeded(action: String) -> Bool {
        let originalSelection = selectedDocumentID
        for documentID in documents.map(\.id) {
            selectedDocumentID = documentID
            updateWindowState()
            guard confirmIfNeeded(action: action) else {
                selectedDocumentID = originalSelection
                updateWindowState()
                return false
            }
        }
        return true
    }

    private static func presentUnsavedChangesAlert(document: EditorDocumentState, action: String) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \(document.displayTitle)?"
        alert.informativeText = "Your changes will be lost if you don’t save them before you \(action)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func presentError(message: String) {
        errorPresenter(message)
    }

    private func presentWarning(title: String, message: String) {
        warningPresenter(title, message)
    }

    private static func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Notepad Error"
        alert.informativeText = message
        alert.runModal()
    }

    private static func presentWarningAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
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
        let storedFontName = defaults.string(forKey: DefaultsKey.fontName)
        let fontName = sanitizeFontName(storedFontName)
        let storedFontSize = defaults.object(forKey: DefaultsKey.fontSize) as? Double ?? EditorPreferences.default.fontSize
        let fontSize = clamp(storedFontSize, to: fontSizeRange)
        let storedLineHeight = defaults.object(forKey: DefaultsKey.lineHeightMultiple) as? Double ?? EditorPreferences.default.lineHeightMultiple
        let lineHeightMultiple = clamp(storedLineHeight, to: lineHeightRange)
        let hasWrapValue = defaults.object(forKey: DefaultsKey.wordWrap) != nil
        let wordWrap = hasWrapValue ? defaults.bool(forKey: DefaultsKey.wordWrap) : EditorPreferences.default.wordWrap

        return EditorPreferences(
            fontName: fontName,
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple,
            wordWrap: wordWrap
        )
    }

    private static func sanitizeFontName(_ fontName: String?) -> String {
        guard let fontName, !fontName.isEmpty else {
            return EditorPreferences.default.fontName
        }

        guard EditorPreferences.availableFonts.contains(fontName),
              NSFont(name: fontName, size: CGFloat(EditorPreferences.default.fontSize)) != nil
        else {
            return EditorPreferences.default.fontName
        }

        return fontName
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    nonisolated static func readPlainText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let utf8Text = String(data: data, encoding: .utf8) {
            return utf8Text
        }
        if (data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])),
           let utf16Text = String(data: data, encoding: .utf16) {
            return utf16Text
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
