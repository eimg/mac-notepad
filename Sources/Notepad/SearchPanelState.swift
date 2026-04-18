import Foundation

struct SearchPanelState: Equatable {
    var isVisible = false
    var query = ""
    var replacement = ""
}

enum SearchCommand: String, Equatable {
    case findNext
    case findPrevious
    case replaceCurrent
    case replaceAll
    case useSelectionForFind
}
