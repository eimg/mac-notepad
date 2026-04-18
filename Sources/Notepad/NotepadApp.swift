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
                .frame(minWidth: 500, minHeight: 360)
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
        VStack(spacing: 0) {
            TabStripView()
            if editor.searchPanel.isVisible {
                SearchBarView()
            }
            PlainTextEditorView(
                text: Binding(
                    get: { editor.currentDocument.text },
                    set: { editor.updateText($0) }
                ),
                preferences: editor.preferences,
                searchPanel: editor.searchPanel,
                searchCommand: editor.searchCommand,
                searchCommandNonce: editor.searchCommandNonce
            )
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

            Button("New Tab") {
                openMainWindow()
                editor.newDocument()
            }
            .keyboardShortcut("t")

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

private struct SearchBarView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullSearchControls
            compactSearchControls
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            editor.hideSearch(reset: true)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var fullSearchControls: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            searchFields
            searchButtons
            closeButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var compactSearchControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                searchFields
                searchButtons
                closeButton
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var searchFields: some View {
        Group {
            SearchInputField(
                title: "Find",
                text: Binding(
                    get: { editor.searchPanel.query },
                    set: { editor.setSearchQuery($0) }
                )
            )
            .frame(width: 220)

            SearchInputField(
                title: "Replace",
                text: Binding(
                    get: { editor.searchPanel.replacement },
                    set: { editor.setReplacementText($0) }
                )
            )
            .frame(width: 220)
        }
    }

    private var searchButtons: some View {
        Group {
            Button("Prev") {
                editor.findPrevious()
            }
            .disabled(editor.searchPanel.query.isEmpty)

            Button("Next") {
                editor.findNext()
            }
            .disabled(editor.searchPanel.query.isEmpty)

            Button("Replace") {
                editor.replaceCurrent()
            }
            .disabled(editor.searchPanel.query.isEmpty)

            Button("Replace All") {
                editor.replaceAll()
            }
            .disabled(editor.searchPanel.query.isEmpty)
        }
    }

    private var closeButton: some View {
        Button {
            editor.hideSearch(reset: true)
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

private struct SearchInputField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .allowsHitTesting(false)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct TabStripView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(editor.documents, id: \.id) { document in
                    TabItemView(document: document)
                }

                Button {
                    editor.newDocument()
                } label: {
                    Image(systemName: "plus")
                        .padding(8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TabItemView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var isHovering = false

    let document: EditorDocumentState

    var body: some View {
        let isActive = document.id == editor.selectedDocumentID

        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(document.displayTitle)
                    .lineLimit(1)
                if document.isDirty {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.secondary)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if editor.documents.count > 1 {
                Button {
                    editor.closeDocument(id: document.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isActive || isHovering ? 0.9 : 0.45)
            }
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.leading, 12)
        .padding(.trailing, editor.documents.count > 1 ? 8 : 12)
        .padding(.vertical, 8)
        .frame(minWidth: 120, maxWidth: 220)
        .background(tabBackground(isActive: isActive))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tabBorder(isActive: isActive), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            editor.selectDocument(document.id)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func tabBackground(isActive: Bool) -> Color {
        if isActive {
            return Color(nsColor: .controlBackgroundColor)
        }
        if isHovering {
            return Color(nsColor: .controlColor).opacity(0.45)
        }
        return Color(nsColor: .quaternaryLabelColor).opacity(0.08)
    }

    private func tabBorder(isActive: Bool) -> Color {
        isActive
            ? Color.accentColor.opacity(0.45)
            : Color(nsColor: .separatorColor).opacity(0.55)
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
