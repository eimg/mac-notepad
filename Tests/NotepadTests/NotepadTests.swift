import Foundation
import Testing
@testable import Notepad

@MainActor
@Test func documentStateTracksDirtyFlagAndTitle() async throws {
    var state = EditorDocumentState()
    #expect(state.displayTitle == "Untitled")
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
    defaults.set(1.3, forKey: "editor.lineHeightMultiple")
    defaults.set(false, forKey: "editor.wordWrap")

    let model = EditorViewModel(defaults: defaults)
    #expect(model.preferences.fontName == "Helvetica")
    #expect(model.preferences.fontSize == 18.0)
    #expect(model.preferences.lineHeightMultiple == 1.3)
    #expect(model.preferences.wordWrap == false)
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
