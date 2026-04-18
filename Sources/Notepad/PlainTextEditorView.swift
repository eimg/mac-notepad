import AppKit
import SwiftUI
import WebKit

struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let preferences: EditorPreferences

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)

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
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "notepadTextChanged"

        private var text: Binding<String>
        private var pageLoaded = false
        private var lastRenderedState: RenderState?

        init(text: Binding<String>) {
            self.text = text
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            applyStateIfNeeded(to: webView, text: text.wrappedValue, preferences: .default, force: true)
            webView.evaluateJavaScript("window.notepad.focusEditor();")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.handlerName, let value = message.body as? String else { return }
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
            if var currentState = lastRenderedState {
                currentState.text = value
                lastRenderedState = currentState
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
