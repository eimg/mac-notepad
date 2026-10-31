import AppKit
import Foundation
import Testing
import WebKit
@testable import Notepad

extension EditorIntegrationTests {
    @Test func nativeEditorDropPreparesAndOpensFilesWithoutReplacingUnsavedText() async throws {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first file.TXT")
        let second = directory.appending(path: "ဒုတိယ.txt")
        try "first file".write(to: first, atomically: true, encoding: .utf8)
        try "မင်္ဂလာပါ".write(to: second, atomically: true, encoding: .utf8)
        let model = EditorViewModel(defaults: UserDefaults(suiteName: "NotepadTests.nativeDrop")!)
        model.updateText("keep this unsaved note")
        let originalID = model.selectedDocumentID
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([first as NSURL, second as NSURL]))
        let drag = FileDraggingInfo(pasteboard: pasteboard)
        let webView = DroppingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.onDroppedFileURLs = { _ = model.openDroppedFileURLs($0) }
        #expect(webView.draggingEntered(drag) == .copy)
        #expect(webView.prepareForDragOperation(drag))
        #expect(webView.performDragOperation(drag))
        try await waitForDrop { model.documents.count == 3 }
        #expect(model.document(id: originalID)?.text == "keep this unsaved note")
        #expect(model.document(id: originalID)?.isDirty == true)
        #expect(model.documents.dropFirst().compactMap(\.fileURL) == [first, second])
        #expect(model.currentDocument.text == "မင်္ဂလာပါ")
        #expect(!model.currentDocument.isDirty)
        // Dropping an already-open file selects its existing tab.
        #expect(model.openDroppedFileURLs([first]))
        #expect(model.documents.count == 3)
        #expect(model.currentDocument.fileURL == first)
    }

    @Test func windowDropUsesTheSamePreparationAndOpeningPath() async throws {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".txt")
        try "window drop".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = EditorViewModel(defaults: UserDefaults(suiteName: "NotepadTests.windowDrop")!)
        let coordinator = DocumentWindowCoordinator(editor: model)
        defer {
            model.resetAfterWindowClose()
            coordinator.synchronize()
        }
        coordinator.showCurrentDocument()
        let controller = coordinator.controllers[model.selectedDocumentID]!
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([url as NSURL]))
        let drag = FileDraggingInfo(pasteboard: pasteboard)
        #expect(controller.prepareForDragOperation(drag))
        #expect(controller.performDragOperation(drag))
        try await waitForDrop { model.currentDocument.fileURL == url }
        #expect(model.documents.count == 1)
        #expect(model.currentDocument.text == "window drop")
    }

    @Test func unsupportedDropsAreRejectedBeforePreparation() throws {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([directory as NSURL, URL(string: "https://example.com/note.txt")! as NSURL]))
        let drag = FileDraggingInfo(pasteboard: pasteboard)
        let webView = DroppingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(webView.draggingEntered(drag).isEmpty)
        #expect(!webView.prepareForDragOperation(drag))
        #expect(!webView.performDragOperation(drag))
        #expect(TextFileDrop.urls(from: pasteboard).isEmpty)
    }

    @Test func providerDropDecodesFileURLsAndKeepsTheirOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appending(path: "one.txt"), directory.appending(path: "two.txt")]
        for url in urls { try url.lastPathComponent.write(to: url, atomically: true, encoding: .utf8) }
        #expect(TextFileDrop.fileURL(from: urls[0] as NSURL) == urls[0])
        #expect(TextFileDrop.fileURL(from: urls[0].dataRepresentation) == urls[0])
        #expect(TextFileDrop.fileURL(from: urls[0].absoluteString as NSString) == urls[0])
        let model = EditorViewModel(defaults: UserDefaults(suiteName: "NotepadTests.providerDrop")!)
        #expect(model.openDroppedItems(from: urls.map { NSItemProvider(object: $0 as NSURL) }))
        try await waitForDrop { model.documents.count == 2 }
        #expect(model.documents.compactMap(\.fileURL) == urls)
        #expect(model.selectedDocumentID == model.documents.last?.id)
    }
}

@MainActor
private func waitForDrop(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

@MainActor
private final class FileDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
