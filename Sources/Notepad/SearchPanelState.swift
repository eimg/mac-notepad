import Foundation

struct SearchPanelState: Equatable {
    var isVisible = false
    var query = ""
    var replacement = ""
    var showsReplacement = false
    var matchCount: Int?
    var currentMatch = 0

    var canNavigate: Bool { !query.isEmpty && (matchCount ?? 0) > 0 }

    var matchSummary: String {
        guard !query.isEmpty else { return "" }
        guard let matchCount else { return "Searching…" }
        guard matchCount > 0 else { return "No matches" }
        return currentMatch > 0 ? "\(currentMatch) of \(matchCount)" : "\(matchCount) matches"
    }
}

struct SearchResults: Equatable {
    let query: String
    let total: Int
    let current: Int
}

enum SearchCommand: String, Equatable {
    case findNext
    case findPrevious
    case replaceCurrent
    case replaceAll
    case useSelectionForFind
    case focusEditor
}
