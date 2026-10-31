import Foundation

struct EditorDocumentState: Equatable, Identifiable {
    let id: UUID
    let untitledNumber: Int
    var fileURL: URL?
    var text: String
    var savedText: String

    init(id: UUID = UUID(), untitledNumber: Int = 1, fileURL: URL? = nil, text: String = "", savedText: String? = nil) {
        self.id = id
        self.untitledNumber = untitledNumber
        self.fileURL = fileURL
        self.text = text
        self.savedText = savedText ?? text
    }

    var isDirty: Bool {
        text != savedText
    }

    var displayTitle: String {
        fileURL?.lastPathComponent ?? "New note \(untitledNumber)"
    }

    var titleWithUnsavedIndicator: String {
        isDirty ? "\(displayTitle) •" : displayTitle
    }
}
