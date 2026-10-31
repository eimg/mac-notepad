import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct NotepadApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

struct DocumentEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var isDropTargeted = false
    let documentID: UUID

    var body: some View {
        VStack(spacing: 0) {
            if editor.selectedDocumentID == documentID && editor.searchPanel.isVisible {
                SearchBarView()
            }
            PlainTextEditorView(
                text: Binding(
                    get: { editor.text(for: documentID) },
                    set: { editor.updateText($0, for: documentID) }
                ),
                preferences: editor.preferences,
                searchPanel: editor.selectedDocumentID == documentID ? editor.searchPanel : SearchPanelState(),
                searchCommand: editor.selectedDocumentID == documentID ? editor.searchCommand : nil,
                searchCommandNonce: editor.searchCommandNonce,
                onSelectionForSearch: { value in
                    if editor.selectedDocumentID == documentID {
                        editor.useSelectionForSearch(value)
                    }
                },
                onSearchResults: { editor.updateSearchResults($0, for: documentID) },
                onCloseSearch: {
                    if editor.selectedDocumentID == documentID { editor.hideSearch() }
                },
                onDroppedFileURLs: { urls in
                    editor.selectDocument(documentID)
                    _ = editor.openDroppedFileURLs(urls)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            editor.openDroppedItems(from: providers, for: documentID)
        }
    }
}

private struct SearchBarView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @FocusState private var focusedField: Field?
    private enum Field { case query, replacement }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    editor.setShowsReplacement(!editor.searchPanel.showsReplacement)
                } label: {
                    Image(systemName: editor.searchPanel.showsReplacement ? "chevron.down" : "chevron.right")
                        .frame(width: 18, height: 22)
                }
                .buttonStyle(.borderless)
                .help(editor.searchPanel.showsReplacement ? "Hide Replace" : "Show Replace")
                .accessibilityLabel(editor.searchPanel.showsReplacement ? "Hide Replace" : "Show Replace")

                TextField("Find", text: Binding(
                    get: { editor.searchPanel.query },
                    set: { editor.setSearchQuery($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .query)
                .onSubmit { editor.findNext() }
                .layoutPriority(1)

                Text(editor.searchPanel.matchSummary)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("Search results: \(editor.searchPanel.matchSummary)")

                Button { editor.findPrevious() } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Previous Match (⇧⌘G)")
                .accessibilityLabel("Previous Match")
                .disabled(!editor.searchPanel.canNavigate)

                Button { editor.findNext() } label: {
                    Image(systemName: "chevron.down")
                }
                .help("Next Match (⌘G)")
                .accessibilityLabel("Next Match")
                .disabled(!editor.searchPanel.canNavigate)

                Button { editor.hideSearch() } label: {
                    Image(systemName: "xmark").frame(width: 18, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Close Find (Esc)")
                .accessibilityLabel("Close Find")
            }

            if editor.searchPanel.showsReplacement {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 18, height: 1)
                    TextField("Replace", text: Binding(
                        get: { editor.searchPanel.replacement },
                        set: { editor.setReplacementText($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .replacement)
                    .onSubmit { editor.replaceCurrent() }
                    .layoutPriority(1)
                    Button("Replace") { editor.replaceCurrent() }
                        .fixedSize()
                        .disabled(!editor.searchPanel.canNavigate)
                    Button("Replace All") { editor.replaceAll() }
                        .fixedSize()
                        .disabled(!editor.searchPanel.canNavigate)
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focusQuery() }
        .onChange(of: editor.searchFocusNonce) { _ in focusQuery() }
        .onExitCommand { editor.hideSearch() }
    }

    private func focusQuery() {
        focusedField = nil
        // Toolbar actions restore the editor's responder after returning. Move
        // focus once the field has been inserted and that restoration is done.
        DispatchQueue.main.async { focusedField = .query }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: DocumentWindowCoordinator?
    private var menus: NotepadMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = EditorViewModel.shared
        let windows = DocumentWindowCoordinator(editor: model)
        self.windows = windows
        menus = NotepadMenuController(editor: model, windows: windows)
        menus?.install()
        windows.showCurrentDocument()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        EditorViewModel.shared.openDocuments(at: urls)
        windows?.synchronize()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        application(sender, open: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        EditorViewModel.shared.confirmTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showCurrentDocument()
        return false
    }

}
