import AppKit
import SwiftUI

@MainActor
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                EditorViewModel.shared.attachWindow(window)
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
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@MainActor
final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        EditorViewModel.shared.confirmClose(window: sender)
    }
}
