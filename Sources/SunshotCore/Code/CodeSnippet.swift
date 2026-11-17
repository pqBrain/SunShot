import Foundation

/// Code-snippet content: the text plus how it is shown. Value type, so undo is trivial.
///
/// Decoding is tolerant (S7 documents): missing keys take their defaults, an unknown language means auto-detect,
/// unknown keys are ignored. Font size and padding are clamped on every write.
public struct CodeSnippet: Codable, Hashable, Sendable {
    public var code: String
    /// The chosen language, or nil to auto-detect from the code.
    public var language: CodeLanguage?
    public var showLineNumbers: Bool
    /// 1-based line numbers drawn with the highlight band.
    public var highlightedLines: Set<Int> {
        didSet { highlightedLines = Self.validLines(highlightedLines) }
    }
    /// Optional title row above the code; empty = no row.
    public var title: String
    /// Code theme id (see `CodeTheme.catalog`); unknown ids render with the default theme.
    public var themeID: String
    /// Text size in canvas pixels at 1×.
    public var fontSize: Double {
        didSet { fontSize = Self.clamp(fontSize, to: Self.fontSizeRange, fallback: Self.defaultFontSize) }
    }
    /// Space between the snippet's edge and the code, in canvas pixels at 1×.
    public var padding: Double {
        didSet { padding = Self.clamp(padding, to: Self.paddingRange, fallback: Self.defaultPadding) }
    }
    /// PostScript name of the monospaced font, or nil for `defaultFontName`.
    public var fontName: String?

    public static let fontSizeRange: ClosedRange<Double> = 8...48
    public static let paddingRange: ClosedRange<Double> = 0...120
    public static let defaultFontSize: Double = 15
    public static let defaultPadding: Double = 28
    public static let defaultFontName = "Menlo-Regular"
    /// `{TEMPLATE}` in export file names for snippet documents.
    public static let templateName = "code"
    /// What a new snippet starts with: short, and shows off several token kinds.
    public static let starterCode = """
        // Sunshot turns code into a picture
        struct Sunrise {
            let hour = 6
            func greet(_ name: String) -> String {
                "Good morning, \\(name)!"
            }
        }
        """

    public init(
        code: String = CodeSnippet.starterCode, language: CodeLanguage? = nil, showLineNumbers: Bool = true,
        highlightedLines: Set<Int> = [], title: String = "", themeID: String = CodeTheme.defaultID,
        fontSize: Double = CodeSnippet.defaultFontSize, padding: Double = CodeSnippet.defaultPadding,
        fontName: String? = nil
    ) {
        self.code = code
        self.language = language
        self.showLineNumbers = showLineNumbers
        self.highlightedLines = Self.validLines(highlightedLines)
        self.title = title
        self.themeID = themeID
        self.fontSize = Self.clamp(fontSize, to: Self.fontSizeRange, fallback: Self.defaultFontSize)
        self.padding = Self.clamp(padding, to: Self.paddingRange, fallback: Self.defaultPadding)
        self.fontName = fontName
    }

    private enum CodingKeys: String, CodingKey {
        case code, language, showLineNumbers, highlightedLines, title, themeID, fontSize, padding, fontName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CodeSnippet()
        let languageName = try? container.decodeIfPresent(String.self, forKey: .language)
        self.init(
            code: (try? container.decodeIfPresent(String.self, forKey: .code)) ?? defaults.code,
            language: languageName.flatMap(CodeLanguage.init(rawValue:)),
            showLineNumbers: (try? container.decodeIfPresent(Bool.self, forKey: .showLineNumbers))
                ?? defaults.showLineNumbers,
            highlightedLines: Set((try? container.decodeIfPresent([Int].self, forKey: .highlightedLines)) ?? []),
            title: (try? container.decodeIfPresent(String.self, forKey: .title)) ?? defaults.title,
            themeID: (try? container.decodeIfPresent(String.self, forKey: .themeID)) ?? defaults.themeID,
            fontSize: (try? container.decodeIfPresent(Double.self, forKey: .fontSize)) ?? defaults.fontSize,
            padding: (try? container.decodeIfPresent(Double.self, forKey: .padding)) ?? defaults.padding,
            fontName: try? container.decodeIfPresent(String.self, forKey: .fontName))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(language?.rawValue, forKey: .language)
        try container.encode(showLineNumbers, forKey: .showLineNumbers)
        try container.encode(highlightedLines.sorted(), forKey: .highlightedLines)
        try container.encode(title, forKey: .title)
        try container.encode(themeID, forKey: .themeID)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(padding, forKey: .padding)
        try container.encodeIfPresent(fontName, forKey: .fontName)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    private static func validLines(_ lines: Set<Int>) -> Set<Int> { lines.filter { $0 >= 1 } }
}

extension CodeSnippet {
    /// The code as measured, highlighted and drawn: LF line endings, tabs as four spaces.
    public var normalizedCode: String { Self.normalize(code) }

    public static func normalize(_ code: String) -> String {
        code.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
    }

    /// The language used for highlighting: the chosen one, or the detected one when auto.
    public var effectiveLanguage: CodeLanguage { language ?? LanguageDetector.detect(code) }

    /// The theme to draw with (the default theme when `themeID` is unknown).
    public var theme: CodeTheme { CodeTheme.theme(id: themeID) }

    /// Theme, line numbers, font size, padding and font back to their defaults; code, language, title and
    /// highlighted lines are kept.
    public func resettingStyle() -> CodeSnippet {
        CodeSnippet(code: code, language: language, highlightedLines: highlightedLines, title: title)
    }
}
