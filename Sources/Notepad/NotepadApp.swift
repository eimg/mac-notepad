import SwiftUI
import UniformTypeIdentifiers

private let mainWindowID = "main-window"

@main
struct NotepadApp: App {
    @StateObject private var editor = EditorViewModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Notepad", id: mainWindowID) {
            ContentView()
                .environmentObject(editor)
                .background(WindowAccessor())
                .background(CursorResetView())
                .frame(minWidth: 500, minHeight: 360)
                .nativeToolbarTitleHidden()
        }
        .commands {
            NotepadCommands(editor: editor, mainWindowID: mainWindowID)
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var isDropTargeted = false

    var body: some View {
        TabView(selection: selectedDocument) {
            ForEach(editor.documents) { document in
                DocumentEditorView(documentID: document.id)
                    .tabItem {
                        Label(tabTitle(for: document), systemImage: document.isDirty ? "circle.fill" : "doc.plaintext")
                    }
                    .tag(document.id)
            }
        }
        .tabViewStyle(.automatic)
        .toolbar {
            NativeEditorToolbar()
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
            editor.openDroppedItems(from: providers)
        }
    }

    private var selectedDocument: Binding<UUID> {
        Binding(
            get: { editor.selectedDocumentID },
            set: { editor.selectDocument($0) }
        )
    }

    private func tabTitle(for document: EditorDocumentState) -> String {
        document.isDirty ? "\(document.displayTitle) ⦁" : document.displayTitle
    }
}

private struct DocumentEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel

    let documentID: UUID

    var body: some View {
        PlainTextEditorView(
            text: Binding(
                get: { editor.text(for: documentID) },
                set: { editor.updateText($0, for: documentID) }
            ),
            preferences: editor.preferences,
            searchPanel: editor.selectedDocumentID == documentID ? editor.searchPanel : SearchPanelState(),
            searchCommand: editor.selectedDocumentID == documentID ? editor.searchCommand : nil,
            searchCommandNonce: editor.searchCommandNonce
        )
    }
}

private struct NativeEditorToolbar: ToolbarContent {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                editor.newDocument()
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .disabled(!editor.canCreateNewDocument)
            .help("New Tab")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                editor.adjustFontSize(by: -1)
            } label: {
                Label("Decrease Font Size", systemImage: "textformat.size.smaller")
            }
            .help("Decrease Font Size")

            Button {
                editor.adjustFontSize(by: 1)
            } label: {
                Label("Increase Font Size", systemImage: "textformat.size.larger")
            }
            .help("Increase Font Size")

            Button {
                editor.showSearch(prefillFromSelection: true)
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find")
            .popover(isPresented: $editor.isSearchPopoverPresented, arrowEdge: .top) {
                SearchPopoverView()
                    .environmentObject(editor)
            }
        }
    }
}

private struct NotepadCommands: Commands {
    @ObservedObject var editor: EditorViewModel
    @Environment(\.openWindow) private var openWindow

    let mainWindowID: String

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                openMainWindow()
                editor.newDocument()
            }
            .keyboardShortcut("n")
            .disabled(!editor.canCreateNewDocument)

            Button("New Tab") {
                openMainWindow()
                editor.newDocument()
            }
            .keyboardShortcut("t")
            .disabled(!editor.canCreateNewDocument)

            Button("Open...") {
                openMainWindow()
                editor.openDocument()
            }
            .keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                openMainWindow()
                _ = editor.saveDocument()
            }
            .keyboardShortcut("s")
            .disabled(!editor.canSave)

            Button("Save As...") {
                openMainWindow()
                _ = editor.saveDocumentAs()
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])

            Button("Close Tab") {
                openMainWindow()
                editor.closeCurrentTab()
            }
            .keyboardShortcut("w")
            .disabled(editor.documents.count <= 1)
        }

        CommandMenu("Format") {
            Picker("Font", selection: fontBinding) {
                ForEach(EditorPreferences.availableFonts, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            Divider()

            Button("Increase Font Size") {
                editor.adjustFontSize(by: 1)
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Decrease Font Size") {
                editor.adjustFontSize(by: -1)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button("Increase Line Height") {
                editor.adjustLineHeight(by: 0.04)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])

            Button("Decrease Line Height") {
                editor.adjustLineHeight(by: -0.04)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Divider()

            Button("Reset Formatting") {
                editor.resetFormatting()
            }

            Divider()

            Toggle("Word Wrap", isOn: wrapBinding)
        }

        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find") {
                openMainWindow()
                editor.showSearch(prefillFromSelection: true)
            }
            .keyboardShortcut("f")

            Button("Find Next") {
                openMainWindow()
                editor.findNext()
            }
            .keyboardShortcut("g")
            .disabled(editor.searchPanel.query.isEmpty)

            Button("Find Previous") {
                openMainWindow()
                editor.findPrevious()
            }
            .keyboardShortcut("G", modifiers: [.command, .shift])
            .disabled(editor.searchPanel.query.isEmpty)

            Button("Replace") {
                openMainWindow()
                editor.showSearch(prefillFromSelection: true)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }

    private var fontBinding: Binding<String> {
        Binding(
            get: { editor.preferences.fontName },
            set: { editor.setFontName($0) }
        )
    }

    private var wrapBinding: Binding<Bool> {
        Binding(
            get: { editor.preferences.wordWrap },
            set: { editor.setWordWrap($0) }
        )
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: mainWindowID)
    }
}

private struct SearchPopoverView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchInputField(
                title: "Find",
                text: Binding(
                    get: { editor.searchPanel.query },
                    set: { editor.setSearchQuery($0) }
                )
            )

            SearchInputField(
                title: "Replace",
                text: Binding(
                    get: { editor.searchPanel.replacement },
                    set: { editor.setReplacementText($0) }
                )
            )

            HStack(spacing: 8) {
                Button {
                    editor.findPrevious()
                } label: {
                    Label("Previous", systemImage: "chevron.up")
                }
                .labelStyle(.iconOnly)
                .help("Find Previous")

                Button {
                    editor.findNext()
                } label: {
                    Label("Next", systemImage: "chevron.down")
                }
                .labelStyle(.iconOnly)
                .help("Find Next")

                Spacer(minLength: 8)

                Button("Replace") {
                    editor.replaceCurrent()
                }

                Button("Replace All") {
                    editor.replaceAll()
                }
            }
            .disabled(editor.searchPanel.query.isEmpty)
        }
        .padding(14)
        .frame(width: 320)
        .onExitCommand {
            editor.hideSearch(reset: true)
        }
    }
}

private struct SearchInputField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}

private extension View {
    @ViewBuilder
    func nativeToolbarTitleHidden() -> some View {
        if #available(macOS 15.0, *) {
            self.toolbar(removing: .title)
        } else {
            self
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        EditorViewModel.shared.openDocuments(at: urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        application(sender, open: urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        EditorViewModel.shared.confirmTermination()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.windows.isEmpty {
            EditorViewModel.shared.resetAfterWindowClose()
        }
    }
}
