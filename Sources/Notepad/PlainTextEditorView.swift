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
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyStateIfNeeded(
            to: webView,
            text: text,
            preferences: preferences
        )
    }

    static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root { color-scheme: light dark; }
        html, body {
          margin: 0;
          width: 100%;
          height: 100%;
          background: transparent;
        }
        textarea {
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          border: 0;
          outline: none;
          resize: none;
          margin: 0;
          padding: 16px 18px;
          background: Canvas;
          color: CanvasText;
          caret-color: AccentColor;
          white-space: pre-wrap;
          overflow-wrap: break-word;
          tab-size: 4;
          spellcheck: false;
        }
        textarea::placeholder {
          color: color-mix(in srgb, CanvasText 45%, transparent);
        }
      </style>
    </head>
    <body>
      <textarea id="editor" placeholder="New note..."></textarea>
      <script>
        const editor = document.getElementById("editor");
        let suppressSend = false;

        function sendValue() {
          if (suppressSend) return;
          window.webkit.messageHandlers.notepadTextChanged.postMessage(editor.value);
        }

        function applyConfig(config) {
          editor.style.fontFamily = config.fontFamily;
          editor.style.fontSize = `${config.fontSize}px`;
          editor.style.lineHeight = `${config.lineHeight}`;
          editor.style.whiteSpace = config.wordWrap ? "pre-wrap" : "pre";
          editor.style.overflowWrap = config.wordWrap ? "break-word" : "normal";
          editor.style.overflowX = config.wordWrap ? "hidden" : "auto";
          editor.wrap = config.wordWrap ? "soft" : "off";
        }

        editor.addEventListener("input", sendValue);

        window.notepad = {
          applyState(state) {
            applyConfig(state.preferences);
            if (editor.value !== state.text) {
              const start = editor.selectionStart;
              const end = editor.selectionEnd;
              suppressSend = true;
              editor.value = state.text;
              const next = Math.min(start, editor.value.length);
              const nextEnd = Math.min(end, editor.value.length);
              editor.setSelectionRange(next, nextEnd);
              suppressSend = false;
            }
          },
          focusEditor() {
            editor.focus();
          }
        };

        requestAnimationFrame(() => {
          window.notepad.focusEditor();
        });
      </script>
    </body>
    </html>
    """

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
