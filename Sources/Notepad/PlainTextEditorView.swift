import AppKit
import SwiftUI
import WebKit

struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let preferences: EditorPreferences
    let searchPanel: SearchPanelState
    let searchCommand: SearchCommand?
    let searchCommandNonce: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.selectionHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        if let editorURL = Bundle.module.url(forResource: "editor", withExtension: "html") {
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "notepadTextChanged"
        static let selectionHandlerName = "notepadSelection"

        private var text: Binding<String>
        private var pageLoaded = false
        private var lastRenderedState: RenderState?
        private var lastSearchCommandNonce = -1
        private var lastSearchPanel = SearchPanelState()

        init(text: Binding<String>) {
            self.text = text
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            applyStateIfNeeded(to: webView, text: text.wrappedValue, preferences: .default, force: true)
            webView.evaluateJavaScript("window.notepad.focusEditor();")
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
                    EditorViewModel.shared.useSelectionForSearch(value)
                }
            }
        }

        func applyStateIfNeeded(to webView: WKWebView, text: String, preferences: EditorPreferences, force: Bool = false) {
            guard pageLoaded else { return }

            let state = RenderState(text: text, preferences: preferences)
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
            guard pageLoaded else { return }

            if panel != lastSearchPanel {
                lastSearchPanel = panel
                if let queryJSON = Self.escapeForJavaScriptString(panel.query),
                   let replacementJSON = Self.escapeForJavaScriptString(panel.replacement) {
                    webView.evaluateJavaScript("window.notepad.updateSearch('\(queryJSON)', '\(replacementJSON)');")
                }
            }

            guard nonce != lastSearchCommandNonce, let command else { return }
            lastSearchCommandNonce = nonce
            webView.evaluateJavaScript("window.notepad.runSearchCommand('\(command.rawValue)');")
        }

        private static func escapeForJavaScriptString(_ value: String) -> String? {
            let data = try? JSONEncoder().encode(value)
            guard let json = data.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return json.dropFirst().dropLast()
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
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
