import AppKit
import Foundation

struct EditorPreferences: Equatable {
    static let availableFonts = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "Helvetica",
        "Avenir Next",
        "Times New Roman",
        "Myanmar MN",
        "Myanmar Sangam MN",
    ]

    var fontName: String
    var fontSize: Double
    var lineHeightMultiple: Double
    var wordWrap: Bool

    static let `default` = EditorPreferences(
        fontName: "Menlo",
        fontSize: 14,
        lineHeightMultiple: 1.18,
        wordWrap: true
    )

    var resolvedFontName: String {
        if NSFont(name: fontName, size: CGFloat(fontSize)) != nil {
            return fontName
        }
        return "Menlo"
    }

    var nsFont: NSFont {
        NSFont(name: resolvedFontName, size: CGFloat(fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    }

    var cssFontFamily: String {
        "\"\(resolvedFontName)\", -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif"
    }

    var lineHeight: CGFloat {
        let baseLineHeight = nsFont.ascender - nsFont.descender + nsFont.leading
        return baseLineHeight * CGFloat(lineHeightMultiple)
    }
}
