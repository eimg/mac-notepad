import AppKit
import SwiftUI
import WebKit

struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let preferences: EditorPreferences
    let searchPanel: SearchPanelState
    let searchCommand: SearchCommand?
    let searchCommandNonce: Int
    let onSelectionForSearch: @MainActor (String) -> Void
    let onSearchResults: @MainActor (SearchResults) -> Void
    let onCloseSearch: @MainActor () -> Void
    let onDroppedFileURLs: @MainActor ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionForSearch: onSelectionForSearch, onSearchResults: onSearchResults, onCloseSearch: onCloseSearch)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.selectionHandlerName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.resultsHandlerName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.closeSearchHandlerName)

        let webView = DroppingWebView(frame: .zero, configuration: configuration)
        webView.onDroppedFileURLs = onDroppedFileURLs
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.registerForDraggedTypes([.fileURL])

        if let editorURL = AppResources.editorHTMLURL {
            webView.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent())
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyStateIfNeeded(
            to: webView,
            text: text,
            preferences: preferences
        )
        context.coordinator.applySearchIfNeeded(
            to: webView,
            panel: searchPanel,
            command: searchCommand,
            nonce: searchCommandNonce
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        for name in [Coordinator.handlerName, Coordinator.selectionHandlerName, Coordinator.resultsHandlerName, Coordinator.closeSearchHandlerName] {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "notepadTextChanged"
        static let selectionHandlerName = "notepadSelection"
        static let resultsHandlerName = "notepadSearchResults"
        static let closeSearchHandlerName = "notepadCloseSearch"

        private var text: Binding<String>
        private var pageLoaded = false
        private var pendingRenderState: RenderState?
        private var lastRenderedState: RenderState?
        private var lastSearchCommandNonce = -1
        private var lastSearchPanel = SearchPanelState()
        private var pendingSearch: (SearchPanelState, SearchCommand?, Int)?
        private let onSelectionForSearch: @MainActor (String) -> Void
        private let onSearchResults: @MainActor (SearchResults) -> Void
        private let onCloseSearch: @MainActor () -> Void

        init(text: Binding<String>, onSelectionForSearch: @escaping @MainActor (String) -> Void, onSearchResults: @escaping @MainActor (SearchResults) -> Void, onCloseSearch: @escaping @MainActor () -> Void = {}) {
            self.text = text
            self.onSelectionForSearch = onSelectionForSearch
            self.onSearchResults = onSearchResults
            self.onCloseSearch = onCloseSearch
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            let state = pendingRenderState ?? RenderState(text: text.wrappedValue, preferences: .default)
            applyRenderStateIfNeeded(to: webView, state: state, force: true)
            if let (panel, command, nonce) = pendingSearch {
                applySearchIfNeeded(to: webView, panel: panel, command: command, nonce: nonce)
            }
            if pendingSearch?.0.isVisible != true {
                webView.evaluateJavaScript("window.notepad.focusEditor();")
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == Self.handlerName, let value = message.body as? String {
                if text.wrappedValue != value {
                    text.wrappedValue = value
                }
                if var currentState = lastRenderedState {
                    currentState.text = value
                    lastRenderedState = currentState
                }
            } else if message.name == Self.selectionHandlerName, let value = message.body as? String {
                Task { @MainActor in
                    onSelectionForSearch(value)
                }
            } else if message.name == Self.closeSearchHandlerName {
                Task { @MainActor in onCloseSearch() }
            } else if message.name == Self.resultsHandlerName,
                      let body = message.body as? [String: Any],
                      let query = body["query"] as? String,
                      let total = body["total"] as? Int,
                      let current = body["current"] as? Int {
                let results = SearchResults(query: query, total: total, current: current)
                Task { @MainActor in onSearchResults(results) }
            }
        }

        func applyStateIfNeeded(to webView: WKWebView, text: String, preferences: EditorPreferences, force: Bool = false) {
            let state = RenderState(text: text, preferences: preferences)
            pendingRenderState = state
            guard pageLoaded else { return }
            applyRenderStateIfNeeded(to: webView, state: state, force: force)
        }

        private func applyRenderStateIfNeeded(to webView: WKWebView, state: RenderState, force: Bool = false) {
            guard force || lastRenderedState != state else { return }
            lastRenderedState = state

            guard
                let jsonData = try? JSONEncoder().encode(state),
                let jsonString = String(data: jsonData, encoding: .utf8)
            else { return }

            let escapedJSON = jsonString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")

            webView.evaluateJavaScript("window.notepad.applyState(JSON.parse('\(escapedJSON)'));")
        }

        func applySearchIfNeeded(to webView: WKWebView, panel: SearchPanelState, command: SearchCommand?, nonce: Int) {
            pendingSearch = (panel, command, nonce)
            guard pageLoaded else { return }

            if panel.query != lastSearchPanel.query || panel.replacement != lastSearchPanel.replacement || panel.isVisible != lastSearchPanel.isVisible {
                lastSearchPanel = panel
                if let queryJSON = Self.javaScriptLiteral(panel.query),
                   let replacementJSON = Self.javaScriptLiteral(panel.replacement) {
                    webView.evaluateJavaScript("window.notepad.updateSearch(\(queryJSON), \(replacementJSON), \(panel.isVisible));")
                }
            }

            guard nonce != lastSearchCommandNonce, let command else { return }
            lastSearchCommandNonce = nonce
            let script = "window.notepad.runSearchCommand('\(command.rawValue)');"
            if command == .focusEditor {
                webView.evaluateJavaScript(script) { [weak webView] _, _ in
                    guard let webView else { return }
                    webView.window?.makeFirstResponder(webView)
                }
            } else {
                webView.evaluateJavaScript(script)
            }
        }

        private static func javaScriptLiteral(_ value: String) -> String? {
            let data = try? JSONEncoder().encode(value)
            guard let json = data.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return json
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        }
    }

    private struct RenderState: Codable, Equatable {
        var text: String
        var preferences: RenderPreferences

        init(text: String, preferences: EditorPreferences) {
            self.text = text
            self.preferences = RenderPreferences(preferences: preferences)
        }
    }

    private struct RenderPreferences: Codable, Equatable {
        var fontFamily: String
        var fontSize: Double
        var lineHeight: Double
        var wordWrap: Bool

        init(preferences: EditorPreferences) {
            self.fontFamily = preferences.cssFontFamily
            self.fontSize = preferences.fontSize
            self.lineHeight = preferences.lineHeightMultiple
            self.wordWrap = preferences.wordWrap
        }
    }
}

private enum AppResources {
    static var editorHTMLURL: URL? {
        if let bundledURL = Bundle.main.url(forResource: "editor", withExtension: "html") {
            return bundledURL
        }

        return developmentResourceURL?.appending(path: "editor.html")
    }

    private static var developmentResourceURL: URL? {
        #if DEBUG
        guard let executableURL = Bundle.main.executableURL else { return nil }

        var directory = executableURL.deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory
                .appending(path: "Sources")
                .appending(path: "Notepad")
                .appending(path: "Resources")

            if FileManager.default.fileExists(atPath: candidate.appending(path: "editor.html").path) {
                return candidate
            }

            directory.deleteLastPathComponent()
        }
        #endif

        return nil
    }
}

final class DroppingWebView: WKWebView {
    var onDroppedFileURLs: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedOperation(for: sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // WKWebView's default prepare step expects WebKit's own drag state.
        // This destination opens documents instead of inserting into the page.
        acceptedOperation(for: sender) == .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {}

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = TextFileDrop.urls(from: sender.draggingPasteboard)
        guard acceptedOperation(for: sender) == .copy, let onDroppedFileURLs else { return false }

        DispatchQueue.main.async {
            onDroppedFileURLs(urls)
        }

        return true
    }

    private func acceptedOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSourceOperationMask.contains(.copy),
              !TextFileDrop.urls(from: sender.draggingPasteboard).isEmpty else { return [] }
        return .copy
    }
}
