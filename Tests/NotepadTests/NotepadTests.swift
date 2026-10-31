import AppKit
import Foundation
import Testing
@testable import Notepad

@MainActor
@Test func documentStateTracksDirtyFlagAndTitle() async throws {
    var state = EditorDocumentState()
    #expect(state.displayTitle == "New note 1")
    #expect(!state.isDirty)

    state.text = "hello"
    #expect(state.isDirty)

    state.savedText = "hello"
    state.fileURL = URL(filePath: "/tmp/example.txt")
    #expect(!state.isDirty)
    #expect(state.displayTitle == "example.txt")
}

@MainActor
@Test func preferencesLoadFromDefaults() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.preferences")!
    defaults.removePersistentDomain(forName: "NotepadTests.preferences")
    defaults.set("Helvetica", forKey: "editor.fontName")
    defaults.set(18.0, forKey: "editor.fontSize")
    defaults.set(1.7, forKey: "editor.lineHeightMultiple")
    defaults.set(false, forKey: "editor.wordWrap")

    let model = EditorViewModel(defaults: defaults)
    #expect(model.preferences.fontName == "Helvetica")
    #expect(model.preferences.fontSize == 18.0)
    #expect(model.preferences.lineHeightMultiple == 1.7)
    #expect(model.preferences.wordWrap == false)
}

@MainActor
@Test func preferencesClampInvalidDefaults() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.invalidPreferences")!
    defaults.removePersistentDomain(forName: "NotepadTests.invalidPreferences")
    defaults.set("Definitely Not A Font", forKey: "editor.fontName")
    defaults.set(200.0, forKey: "editor.fontSize")
    defaults.set(0.2, forKey: "editor.lineHeightMultiple")

    let model = EditorViewModel(defaults: defaults)

    #expect(model.preferences.fontName == EditorPreferences.default.fontName)
    #expect(model.preferences.fontSize == 36.0)
    #expect(model.preferences.lineHeightMultiple == 1.5)
}

@MainActor
@Test func resetFormattingRestoresDefaults() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.resetFormatting")!
    defaults.removePersistentDomain(forName: "NotepadTests.resetFormatting")

    let model = EditorViewModel(defaults: defaults)
    model.setFontName("Helvetica")
    model.adjustFontSize(by: 4)
    model.adjustLineHeight(by: 0.12)
    model.setWordWrap(false)

    model.resetFormatting()

    #expect(model.preferences == .default)
}

@MainActor
@Test func openingSameFileSelectsExistingDocument() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.duplicateOpen")!
    defaults.removePersistentDomain(forName: "NotepadTests.duplicateOpen")

    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    try "hello".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let model = EditorViewModel(defaults: defaults)
    model.openDocument(at: url)
    let openedDocumentID = model.selectedDocumentID

    model.newDocument()
    #expect(model.documents.count == 2)

    model.openDocument(at: url)

    #expect(model.documents.count == 2)
    #expect(model.selectedDocumentID == openedDocumentID)
}

@MainActor
@Test func openingFilesRespectsMaximumDocumentCount() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.maxDocuments")!
    defaults.removePersistentDomain(forName: "NotepadTests.maxDocuments")

    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = EditorViewModel(defaults: defaults)
    var urls = [URL]()
    for index in 0...EditorViewModel.maxDocumentCount {
        let url = directory.appending(path: "note-\(index)").appendingPathExtension("txt")
        try "note \(index)".write(to: url, atomically: true, encoding: .utf8)
        urls.append(url)
    }

    for url in urls {
        model.openDocument(at: url)
    }

    #expect(model.documents.count == EditorViewModel.maxDocumentCount)
    #expect(model.documents.allSatisfy { $0.fileURL != urls.last })
}

@MainActor
@Test func closingWindowPromptsForDirtyBackgroundTabs() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.closeDirtyBackgroundTabs")!
    defaults.removePersistentDomain(forName: "NotepadTests.closeDirtyBackgroundTabs")

    var promptedDocuments = [String]()
    let model = EditorViewModel(
        defaults: defaults,
        unsavedChangesDecision: { document, _ in
            promptedDocuments.append(document.text)
            return .discard
        }
    )

    model.updateText("dirty background")
    model.newDocument()
    #expect(model.documents.count == 2)
    #expect(model.currentDocument.text.isEmpty)

    let window = NSWindow()
    let shouldClose = model.confirmClose(window: window)

    #expect(shouldClose)
    #expect(promptedDocuments == ["dirty background"])
    #expect(model.documents.count == 1)
    #expect(model.currentDocument.text.isEmpty)
}

@MainActor
@Test func saveAsRejectsURLAlreadyOpenInAnotherTab() async throws {
    let defaults = UserDefaults(suiteName: "NotepadTests.saveAsDuplicateURL")!
    defaults.removePersistentDomain(forName: "NotepadTests.saveAsDuplicateURL")

    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    try "original".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    var warnings = [(title: String, message: String)]()
    let model = EditorViewModel(
        defaults: defaults,
        warningPresenter: { title, message in
            warnings.append((title, message))
        }
    )
    model.openDocument(at: url)
    model.newDocument()
    model.updateText("replacement")

    let didSave = model.saveCurrentDocument(to: url)

    #expect(!didSave)
    #expect(model.documents.count == 2)
    #expect(model.currentDocument.fileURL == nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "original")
    #expect(warnings.count == 1)
    #expect(warnings.first?.title == "File Already Open")
    #expect(warnings.first?.message == "\(url.lastPathComponent) is already open in another tab. Close that tab before saving this note to the same file.")
}

@Test func readsUTF8TextFiles() async throws {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    try "hello".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let value = try EditorViewModel.readPlainText(from: url)
    #expect(value == "hello")
}

@Test func readsUTF16TextFilesWithByteOrderMark() async throws {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    var data = Data([0xFF, 0xFE])
    data.append("hello".data(using: .utf16LittleEndian)!)
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let value = try EditorViewModel.readPlainText(from: url)
    #expect(value == "hello")
}

@Test func rejectsNonUTF8Data() async throws {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    try Data([0xFF, 0x00, 0xFE]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(throws: CocoaError.self) {
        try EditorViewModel.readPlainText(from: url)
    }
}

@MainActor
@Test func untitledNamesStayStableAndAreNotReusedWhenTabsClose() {
    let model = EditorViewModel(defaults: tabTestDefaults("numbering"))
    let firstID = model.selectedDocumentID
    model.newDocument()
    let secondID = model.selectedDocumentID

    #expect(model.documents.map(\.displayTitle) == ["New note 1", "New note 2"])
    model.closeDocument(id: firstID)
    #expect(model.selectedDocumentID == secondID)
    #expect(model.currentDocument.displayTitle == "New note 2")

    model.newDocument()
    #expect(model.documents.map(\.displayTitle) == ["New note 2", "New note 3"])
}

@MainActor
@Test(arguments: [true, false])
func closingDirtyBackgroundTabPreservesActiveTab(discard: Bool) {
    var promptedIDs = [UUID]()
    let model = EditorViewModel(
        defaults: tabTestDefaults("background-\(discard)"),
        unsavedChangesDecision: { document, _ in
            promptedIDs.append(document.id)
            return discard ? .discard : .cancel
        }
    )
    model.updateText("မင်္ဂလာပါ")
    let backgroundID = model.selectedDocumentID
    model.newDocument()
    let activeID = model.selectedDocumentID

    model.closeDocument(id: backgroundID)

    #expect(promptedIDs == [backgroundID])
    #expect(model.selectedDocumentID == activeID)
    #expect(model.documents.count == (discard ? 1 : 2))
    #expect((model.document(id: backgroundID) == nil) == discard)
}

@MainActor
@Test func closingSelectedTabSelectsNeighborAndClearsSearch() {
    let model = EditorViewModel(defaults: tabTestDefaults("neighbor"))
    model.newDocument()
    let middleID = model.selectedDocumentID
    model.newDocument()
    let rightID = model.selectedDocumentID
    model.selectDocument(middleID)
    model.showSearch()
    model.setSearchQuery("old query")

    model.closeCurrentTab()

    #expect(model.selectedDocumentID == rightID)
    #expect(model.documents.count == 2)
    #expect(model.searchPanel.query.isEmpty)
    #expect(!model.searchPanel.isVisible)
}

@MainActor
@Test(arguments: [true, false])
func closingLastDirtyTabHonorsUnsavedDecision(discard: Bool) {
    var promptCount = 0
    let model = EditorViewModel(
        defaults: tabTestDefaults("last-\(discard)"),
        unsavedChangesDecision: { _, _ in
            promptCount += 1
            return discard ? .discard : .cancel
        }
    )
    let window = CloseTrackingWindow()
    model.attachWindow(window)
    model.updateText("unsaved မင်္ဂလာပါ")
    let originalID = model.selectedDocumentID

    model.closeCurrentTab()

    #expect(promptCount == 1)
    #expect(window.closeCount == (discard ? 1 : 0))
    #expect(model.isWindowOpen == !discard)
    #expect(model.documents.count == 1)
    if discard {
        #expect(model.selectedDocumentID != originalID)
        #expect(model.currentDocument.text.isEmpty)
        #expect(!model.currentDocument.isDirty)
    } else {
        #expect(model.selectedDocumentID == originalID)
        #expect(model.currentDocument.text == "unsaved မင်္ဂလာပါ")
        #expect(model.currentDocument.isDirty)
    }
}

@MainActor
@Test(arguments: [true, false])
func closingLastTabOnlyClosesAfterSuccessfulSave(saveSucceeds: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "note.txt")
    try "original".write(to: url, atomically: true, encoding: .utf8)
    var errors = [String]()
    var promptCount = 0
    let model = EditorViewModel(
        defaults: tabTestDefaults("save-\(saveSucceeds)"),
        unsavedChangesDecision: { _, _ in
            promptCount += 1
            return .save
        },
        errorPresenter: { errors.append($0) }
    )
    let window = CloseTrackingWindow()
    model.attachWindow(window)
    model.openDocument(at: url)
    model.updateText("saved မင်္ဂလာပါ")
    let originalID = model.selectedDocumentID
    if !saveSucceeds {
        try FileManager.default.removeItem(at: directory)
    }

    model.closeCurrentTab()

    #expect(promptCount == 1)
    #expect(window.closeCount == (saveSucceeds ? 1 : 0))
    #expect(model.isWindowOpen == !saveSucceeds)
    if saveSucceeds {
        #expect(try String(contentsOf: url, encoding: .utf8) == "saved မင်္ဂလာပါ")
        #expect(errors.isEmpty)
        #expect(model.currentDocument.text.isEmpty)
    } else {
        #expect(errors.count == 1)
        #expect(model.selectedDocumentID == originalID)
        #expect(model.currentDocument.text == "saved မင်္ဂလာပါ")
        #expect(model.currentDocument.isDirty)
    }
}

@MainActor
@Test func closingLastCleanTabDoesNotPrompt() {
    var promptCount = 0
    let model = EditorViewModel(
        defaults: tabTestDefaults("clean-last"),
        unsavedChangesDecision: { _, _ in
            promptCount += 1
            return .cancel
        }
    )
    let window = CloseTrackingWindow()
    model.attachWindow(window)

    model.closeCurrentTab()

    #expect(promptCount == 0)
    #expect(window.closeCount == 1)
    #expect(!model.isWindowOpen)
    #expect(model.documents.count == 1)
    #expect(!model.currentDocument.isDirty)
}

private func tabTestDefaults(_ name: String) -> UserDefaults {
    let suiteName = "NotepadTests.tabs.\(name)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private final class CloseTrackingWindow: NSWindow {
    private(set) var closeCount = 0

    override func close() {
        closeCount += 1
        // These unit tests do not display a window; live window behavior is
        // verified separately in the app.
    }
}

@Suite(.serialized)
@MainActor
struct EditorIntegrationTests {
    @Test func nativeTabsKeepTheirWindowsAndHonorBackgroundCloseDecisions() async {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        var discard = false
        var prompts = [UUID]()
        let model = EditorViewModel(
            defaults: tabTestDefaults("native-background"),
            unsavedChangesDecision: { document, _ in
                prompts.append(document.id)
                return discard ? .discard : .cancel
            }
        )
        let coordinator = DocumentWindowCoordinator(editor: model)
        defer {
            model.resetAfterWindowClose()
            coordinator.synchronize()
        }
        coordinator.showCurrentDocument()
        let firstID = model.selectedDocumentID
        let firstWindow = coordinator.controllers[firstID]!.window!
        model.updateText("မင်္ဂလာပါ")
        coordinator.newDocument()
        let secondID = model.selectedDocumentID
        let secondWindow = coordinator.controllers[secondID]!.window!
        #expect(firstWindow.tabbedWindows?.count == 2)
        #expect(secondWindow.toolbar?.items.map(\.itemIdentifier) == [
            DocumentWindowController.newTabItem, .flexibleSpace, DocumentWindowController.titleItem, .flexibleSpace,
            DocumentWindowController.fontItem, .space, DocumentWindowController.findItem
        ])
        #expect(secondWindow.toolbar?.centeredItemIdentifiers == [DocumentWindowController.titleItem])

        firstWindow.performClose(nil)
        coordinator.synchronize()
        #expect(prompts == [firstID])
        #expect(model.documents.count == 2)
        #expect(model.selectedDocumentID == secondID)
        #expect(coordinator.controllers[firstID]?.window === firstWindow)
        #expect(coordinator.controllers[secondID]?.window === secondWindow)

        discard = true
        firstWindow.performClose(nil)
        coordinator.synchronize()
        #expect(prompts == [firstID, firstID])
        #expect(model.documents.count == 1)
        #expect(model.selectedDocumentID == secondID)
        #expect(coordinator.controllers[firstID] == nil)
        #expect(coordinator.controllers[secondID]?.window === secondWindow)
        #expect(secondWindow.toolbar?.items.first?.itemIdentifier == DocumentWindowController.newTabItem)
        #expect(await singleNoteTabBarIsHidden(in: secondWindow))
    }

    @Test func closingLastNativeTabAndReopeningCreatesExactlyOneFreshNote() async {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        let model = EditorViewModel(defaults: tabTestDefaults("native-reopen"))
        let coordinator = DocumentWindowCoordinator(editor: model)
        defer {
            model.resetAfterWindowClose()
            coordinator.synchronize()
        }
        coordinator.showCurrentDocument()
        let originalID = model.selectedDocumentID
        #expect(await singleNoteTabBarIsHidden(in: coordinator.controllers[originalID]!.window!))
        coordinator.controllers[originalID]?.window?.performClose(nil)
        coordinator.synchronize()
        #expect(!model.isWindowOpen)
        #expect(coordinator.controllers.isEmpty)

        coordinator.newDocument()
        #expect(model.isWindowOpen)
        #expect(model.documents.count == 1)
        #expect(coordinator.controllers.count == 1)
        #expect(model.selectedDocumentID != originalID)
        #expect(model.currentDocument.text.isEmpty)
        #expect(await singleNoteTabBarIsHidden(in: coordinator.controllers[model.selectedDocumentID]!.window!))
    }
}

@MainActor
private func singleNoteTabBarIsHidden(in window: NSWindow) async -> Bool {
    let deadline = Date().addingTimeInterval(1)
    while window.tabGroup?.isTabBarVisible == true && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return window.tabGroup?.isTabBarVisible != true
}
