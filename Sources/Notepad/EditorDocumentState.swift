import Foundation

struct EditorDocumentState: Equatable {
    let id: UUID
    var fileURL: URL?
    var text: String
    var savedText: String

    init(id: UUID = UUID(), fileURL: URL? = nil, text: String = "", savedText: String? = nil) {
        self.id = id
        self.fileURL = fileURL
        self.text = text
        self.savedText = savedText ?? text
    }

    var isDirty: Bool {
        text != savedText
    }

    var displayTitle: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }
}
