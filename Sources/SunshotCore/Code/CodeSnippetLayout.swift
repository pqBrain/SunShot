import Foundation

/// Font measurements the layout needs, supplied by the renderer (CoreText) in canvas pixels at 1×.
public struct CodeFontMetrics: Hashable, Sendable {
    /// Advance of one monospaced column (the digit "0").
    public let advance: Double
    public let ascent: Double
    public let descent: Double

    public init(advance: Double, ascent: Double, descent: Double) {
        self.advance = advance
        self.ascent = ascent
        self.descent = descent
    }
}

/// Where everything in a snippet goes, in canvas pixels at 1× with a top-left origin.
///
/// width  = padding + gutter + max(longest line, `minimumColumns` columns) + padding
/// height = padding + title row + lines × line height + padding (both rounded up to whole pixels).
public struct CodeSnippetLayout: Hashable, Sendable {
    public static let minimumColumns = 24
    public static let minimumGutterDigits = 2

    public let size: PixelSize
    public let lineCount: Int
    public let lineHeight: Double
    /// 0 when the title is empty.
    public let titleHeight: Double
    /// 0 when line numbers are off; otherwise digits × advance + a gap of one line height.
    public let gutterWidth: Double
    public let padding: Double
    /// Distance from a line's top to its text baseline.
    public let baselineOffset: Double

    public static func lineHeight(fontSize: Double) -> Double { (fontSize * 1.5).rounded() }
    public static func titleHeight(fontSize: Double) -> Double { (fontSize * 2.4).rounded() }

    /// Lines of the normalised code (an empty text is one line; a trailing newline adds an empty line).
    public static func lines(of normalizedCode: String) -> [Substring] {
        normalizedCode.split(separator: "\n", omittingEmptySubsequences: false)
    }

    public init(snippet: CodeSnippet, lineWidths: [Double], metrics: CodeFontMetrics) {
        let fontSize = snippet.fontSize
        lineCount = max(1, lineWidths.count)
        lineHeight = Self.lineHeight(fontSize: fontSize)
        titleHeight = snippet.title.isEmpty ? 0 : Self.titleHeight(fontSize: fontSize)
        padding = snippet.padding
        let digits = max(Self.minimumGutterDigits, String(lineCount).count)
        gutterWidth = snippet.showLineNumbers ? Double(digits) * metrics.advance + lineHeight : 0
        let longest = lineWidths.max() ?? 0
        let textWidth = max(longest, Double(Self.minimumColumns) * metrics.advance)
        let width = padding * 2 + gutterWidth + textWidth
        let height = padding * 2 + titleHeight + Double(lineCount) * lineHeight
        size = PixelSize(width: Int(width.rounded(.up)), height: Int(height.rounded(.up)))
        let glyphHeight = metrics.ascent + metrics.descent
        baselineOffset = ((lineHeight - glyphHeight) / 2 + metrics.ascent).rounded()
    }

    /// x where code text starts.
    public var textX: Double { padding + gutterWidth }
    /// x where right-aligned line numbers end.
    public var numbersRight: Double { gutterWidth > 0 ? textX - lineHeight : textX }
    /// y of the first code line's top.
    public var codeTop: Double { padding + titleHeight }

    /// The full-width band of 0-based line `index` (used for highlighted lines).
    public func lineBand(_ index: Int) -> LayoutRect {
        LayoutRect(
            x: 0, y: codeTop + Double(index) * lineHeight, width: Double(size.width), height: lineHeight)
    }

    /// The title row (zero height when there's no title).
    public var titleRect: LayoutRect {
        LayoutRect(x: padding, y: padding, width: Double(size.width) - padding * 2, height: titleHeight)
    }
}
