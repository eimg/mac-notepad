import AppKit
import SwiftUI

struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let preferences: EditorPreferences

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !preferences.wordWrap
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .textBackgroundColor
        textView.string = text

        configure(textView: textView, in: scrollView)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        configure(textView: textView, in: scrollView)
        context.coordinator.focusIfNeeded(textView)
    }

    private func configure(textView: NSTextView, in scrollView: NSScrollView) {
        textView.font = preferences.nsFont
        textView.isHorizontallyResizable = !preferences.wordWrap
        textView.autoresizingMask = preferences.wordWrap ? [.width] : []
        scrollView.hasHorizontalScroller = !preferences.wordWrap
        applyParagraphStyle(to: textView)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = preferences.wordWrap
            textContainer.containerSize = preferences.wordWrap
                ? NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                : NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
    }

    private func applyParagraphStyle(to textView: NSTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = preferences.lineHeight
        paragraphStyle.maximumLineHeight = preferences.lineHeight
        let textColor = NSColor.textColor

        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        textView.typingAttributes[.font] = preferences.nsFont
        textView.typingAttributes[.foregroundColor] = textColor
        textView.textColor = textColor

        let attributedText = NSMutableAttributedString(string: textView.string)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.addAttribute(.font, value: preferences.nsFont, range: fullRange)
        attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        attributedText.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        textView.textStorage?.setAttributedString(attributedText)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var hasFocusedEditor = false

        init(text: Binding<String>) {
            self.text = text
        }

        @MainActor
        func focusIfNeeded(_ textView: NSTextView) {
            guard !hasFocusedEditor, let window = textView.window else { return }

            hasFocusedEditor = true
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
