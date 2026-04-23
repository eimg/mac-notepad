import AppKit
import SwiftUI

@MainActor
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                EditorViewModel.shared.attachWindow(window)
                WindowDelegate.shared.trackCursor(in: window)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                EditorViewModel.shared.attachWindow(window)
                WindowDelegate.shared.trackCursor(in: window)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@MainActor
struct CursorResetView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CursorResetNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CursorResetNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
}

@MainActor
final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    private weak var cursorWindow: NSWindow?
    private var cursorMonitor: Any?

    func trackCursor(in window: NSWindow) {
        guard cursorWindow !== window else { return }

        cursorWindow = window
        window.acceptsMouseMovedEvents = true

        if let cursorMonitor {
            NSEvent.removeMonitor(cursorMonitor)
        }

        cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak window] event in
            guard let window, event.window === window else { return event }

            if !window.contentLayoutRect.contains(event.locationInWindow) {
                NSCursor.arrow.set()
            }

            return event
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        EditorViewModel.shared.confirmClose(window: sender)
    }
}
