import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import Notepad

extension EditorIntegrationTests {
    @Test func burmeseSearchCountsAndWrapsInBothDirections() async throws {
        let text = "မင်္ဂလာပါ\nEnglish text\nမင်္ဂလာပါ"
        let harness = SearchHarness(text: text)
        defer { harness.close() }
        try await harness.load()
        harness.search(query: "မင်္ဂလာပါ")
        try await harness.waitForResults(query: "မင်္ဂလာပါ", total: 2, current: 1)
        #expect(try await harness.selectedText() == "မင်္ဂလာပါ")
        harness.command(.findNext)
        try await harness.waitForResults(query: "မင်္ဂလာပါ", total: 2, current: 2)
        harness.command(.findNext)
        try await harness.waitForResults(query: "မင်္ဂလာပါ", total: 2, current: 1)
        // The reverse wrap must include matches on the final line.
        harness.command(.findPrevious)
        try await harness.waitForResults(query: "မင်္ဂလာပါ", total: 2, current: 2)
        harness.search(query: "missing")
        try await harness.waitForResults(query: "missing", total: 0, current: 0)
        harness.search(query: "မင်္ဂလာပါ")
        try await harness.waitForResults(query: "မင်္ဂလာပါ", total: 2, current: 2)
        _ = try await harness.value("editor.getInputField().dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', keyCode:27, bubbles:true, cancelable:true}))")
        try await harness.waitForCloseRequest()
        harness.hideSearch()
        try await harness.waitForResults(query: "မင်္ဂလာပါ", total: 0, current: 0)
        #expect(try await harness.value("searchMarks.length") as? Int == 0)
        #expect(harness.state.text == text)
    }

    @Test func bridgePreservesLiteralCharactersAndReplaceAllUndoesAsOneEdit() async throws {
        let needle = "C:\\notes.txt \"quote\" 'single'"
        let replacement = "D:\\မင်္ဂလာပါ.txt"
        let text = "\(needle)\n\(needle)"
        let harness = SearchHarness(text: text)
        defer { harness.close() }
        try await harness.load()
        harness.search(query: needle, replacement: replacement)
        let actualQuery = try await harness.value("searchQuery") as? String
        #expect(actualQuery == needle)
        try await harness.waitForResults(query: needle, total: 2, current: 1)
        harness.command(.replaceAll)
        try await harness.waitForText("\(replacement)\n\(replacement)")
        try await harness.waitForResults(query: needle, total: 0, current: 0)
        _ = try await harness.value("editor.execCommand('undo')")
        try await harness.waitForText(text)
        try await harness.waitForResults(query: needle, total: 2)
        // Real line breaks must survive JSON transport, too.
        harness.search(query: text, replacement: "one note")
        try await harness.waitForResults(query: text, total: 1, current: 1)
        harness.command(.replaceCurrent)
        try await harness.waitForText("one note")
        try await harness.waitForResults(query: text, total: 0)
    }
}

@MainActor
private final class SearchHarness {
    final class State {
        var text: String
        var results: SearchResults?
        var closeRequested = false
        init(text: String) { self.text = text }
    }
    let state: State
    private let coordinator: PlainTextEditorView.Coordinator
    private let webView: WKWebView
    private var panel = SearchPanelState()
    private var nonce = 0

    init(text: String) {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        let state = State(text: text)
        self.state = state
        coordinator = PlainTextEditorView.Coordinator(
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            onSelectionForSearch: { _ in },
            onSearchResults: { state.results = $0 },
            onCloseSearch: { state.closeRequested = true }
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        for name in ["notepadTextChanged", "notepadSelection", "notepadSearchResults", "notepadCloseSearch"] {
            configuration.userContentController.add(coordinator, name: name)
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        webView.navigationDelegate = coordinator
        coordinator.applyStateIfNeeded(to: webView, text: text, preferences: .default)
        coordinator.applySearchIfNeeded(to: webView, panel: panel, command: nil, nonce: nonce)
    }

    func load() async throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appending(path: "Sources/Notepad/Resources/editor.html")
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        let expected = state.text
        try await waitUntil {
            (try? await self.value("window.notepad && editor.getValue()") as? String) == expected
        }
    }

    func search(query: String, replacement: String = "") {
        panel.isVisible = true
        panel.query = query
        panel.replacement = replacement
        nonce += 1
        coordinator.applySearchIfNeeded(to: webView, panel: panel, command: nil, nonce: nonce)
    }

    func command(_ command: SearchCommand) {
        nonce += 1
        coordinator.applySearchIfNeeded(to: webView, panel: panel, command: command, nonce: nonce)
    }

    func hideSearch() {
        panel.isVisible = false
        command(.focusEditor)
    }

    func value(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func selectedText() async throws -> String? {
        try await value("editor.getSelection()") as? String
    }

    func waitForResults(query: String, total: Int, current: Int? = nil) async throws {
        let normalized = query.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        try await waitUntil {
            self.state.results?.query == normalized && self.state.results?.total == total &&
                (current == nil || self.state.results?.current == current)
        }
    }

    func waitForText(_ expected: String) async throws {
        try await waitUntil { self.state.text == expected }
    }

    func waitForCloseRequest() async throws {
        try await waitUntil { self.state.closeRequested }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let diagnostic = try? await value("JSON.stringify({query:searchQuery,text:editor.getValue(),contains:editor.getValue().includes(searchQuery),total:matches.length})")
        throw NSError(domain: "EditorSearchTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Editor did not reach the expected state. Text: \(state.text), results: \(String(describing: state.results)), JavaScript: \(String(describing: diagnostic))"
        ])
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for name in ["notepadTextChanged", "notepadSelection", "notepadSearchResults", "notepadCloseSearch"] {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }
}

@MainActor
final class NotepadTestApplicationDelegate: NSObject, NSApplicationDelegate {
    static let shared = NotepadTestApplicationDelegate()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}

extension EditorIntegrationTests {
    @Test func dirtyIndicatorsFollowSavesAndTabGrouping() throws {
        NSApplication.shared.delegate = NotepadTestApplicationDelegate.shared
        let model = EditorViewModel(defaults: UserDefaults(suiteName: "NotepadTests.indicators")!)
        let coordinator = DocumentWindowCoordinator(editor: model)
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".txt")
        defer {
            model.resetAfterWindowClose()
            coordinator.synchronize()
            try? FileManager.default.removeItem(at: url)
        }
        coordinator.showCurrentDocument()
        let firstID = model.selectedDocumentID
        let firstWindow = coordinator.controllers[firstID]!.window!
        func title() -> String? {
            (firstWindow.toolbar?.items.first { $0.itemIdentifier == DocumentWindowController.titleItem }?.view as? NSTextField)?.stringValue
        }
        #expect(firstWindow.tab.title == model.currentDocument.displayTitle)
        #expect(title() == model.currentDocument.displayTitle)
        model.updateText("မင်္ဂလာပါ")
        coordinator.synchronize()
        #expect(firstWindow.tab.title.hasSuffix(" •"))
        #expect(title()?.hasSuffix(" •") == true)
        coordinator.newDocument()
        let secondID = model.selectedDocumentID
        #expect(firstWindow.tab.title.hasSuffix(" •"))
        #expect(title()?.hasSuffix(" •") == false)
        model.selectDocument(firstID)
        #expect(model.saveCurrentDocument(to: url))
        coordinator.synchronize()
        #expect(firstWindow.tab.title == url.lastPathComponent)
        model.updateText("edited")
        coordinator.synchronize()
        #expect(firstWindow.tab.title.hasSuffix(" •"))
        model.updateText("မင်္ဂလာပါ")
        coordinator.synchronize()
        #expect(firstWindow.tab.title == url.lastPathComponent)
        model.updateText("edited again")
        model.closeDocument(id: secondID)
        coordinator.synchronize()
        #expect(title() == url.lastPathComponent + " •")
    }
}

@MainActor
@Test func searchResultsIgnoreStaleQueriesAndBackgroundDocuments() {
    let model = EditorViewModel(defaults: UserDefaults(suiteName: "NotepadTests.searchResults")!)
    let firstID = model.selectedDocumentID
    model.showSearch(replacing: true)
    model.setSearchQuery("first")
    model.updateSearchResults(SearchResults(query: "old", total: 9, current: 1), for: firstID)
    #expect(model.searchPanel.matchCount == nil)
    model.updateSearchResults(SearchResults(query: "first", total: 2, current: 1), for: firstID)
    #expect(model.searchPanel.matchSummary == "1 of 2")
    #expect(model.searchPanel.showsReplacement)
    model.newDocument()
    model.showSearch()
    model.setSearchQuery("first")
    model.updateSearchResults(SearchResults(query: "first", total: 2, current: 1), for: firstID)
    #expect(model.searchPanel.matchCount == nil)
    model.updateSearchResults(SearchResults(query: "first", total: 0, current: 0), for: model.selectedDocumentID)
    #expect(model.searchPanel.matchSummary == "No matches")
    #expect(!model.searchPanel.canNavigate)
    model.hideSearch()
    #expect(model.searchCommand == .focusEditor)
    #expect(model.searchPanel.query == "first")
}
