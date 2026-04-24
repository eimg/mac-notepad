import Foundation
import Testing
@testable import Notepad

@MainActor
@Test func documentStateTracksDirtyFlagAndTitle() async throws {
    var state = EditorDocumentState()
    #expect(state.displayTitle == "New note")
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

@Test func readsUTF8TextFiles() async throws {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    try "hello".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let value = try EditorViewModel.readPlainText(from: url)
    #expect(value == "hello")
}

@Test func rejectsNonUTF8Data() async throws {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("txt")
    try Data([0xFF, 0xFE, 0x00, 0x00]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(throws: CocoaError.self) {
        try EditorViewModel.readPlainText(from: url)
    }
}
