import Foundation
import Testing

@testable import SunshotCore

@Suite("Code snippet model")
struct CodeSnippetModelTests {
    @Test("[S11-AC2] defaults")
    func defaults() {
        let snippet = CodeSnippet()
        #expect(snippet.code == CodeSnippet.starterCode)
        #expect(snippet.language == nil)
        #expect(snippet.showLineNumbers)
        #expect(snippet.highlightedLines.isEmpty)
        #expect(snippet.title.isEmpty)
        #expect(snippet.themeID == "daybreak")
        #expect(snippet.theme.isDark == false)
        #expect(snippet.fontSize == 15)
        #expect(snippet.padding == 28)
        #expect(snippet.fontName == nil)
        #expect(CodeSnippet.defaultFontName == "Menlo-Regular")
        #expect(snippet.effectiveLanguage == .swift)
    }

    @Test("[S11-AC2] font size, padding and highlighted lines are clamped")
    func clamping() {
        var snippet = CodeSnippet(highlightedLines: [0, -3, 2], fontSize: 2, padding: 500)
        #expect(snippet.fontSize == 8)
        #expect(snippet.padding == 120)
        #expect(snippet.highlightedLines == [2])
        snippet.fontSize = 99
        snippet.padding = -4
        snippet.highlightedLines = [0, 5]
        #expect(snippet.fontSize == 48)
        #expect(snippet.padding == 0)
        #expect(snippet.highlightedLines == [5])
        snippet.fontSize = .nan
        snippet.padding = .infinity
        #expect(snippet.fontSize == CodeSnippet.defaultFontSize)
        #expect(snippet.padding == CodeSnippet.defaultPadding)
    }

    @Test("[S11-AC3] round-trips through JSON with every field set")
    func roundTrip() throws {
        let snippet = CodeSnippet(
            code: "SELECT 1;", language: .sql, showLineNumbers: false, highlightedLines: [1, 3], title: "Query",
            themeID: "ember", fontSize: 20, padding: 10, fontName: "Courier")
        let data = try JSONEncoder().encode(snippet)
        #expect(try JSONDecoder().decode(CodeSnippet.self, from: data) == snippet)
        let auto = CodeSnippet(code: "x")
        #expect(try JSONDecoder().decode(CodeSnippet.self, from: JSONEncoder().encode(auto)) == auto)
    }

    @Test("[S11-AC3] tolerant decoding: missing keys, unknown language, unknown theme, extra keys")
    func tolerantDecoding() throws {
        let empty = try JSONDecoder().decode(CodeSnippet.self, from: Data("{}".utf8))
        #expect(empty == CodeSnippet())
        let json = """
            {"code": "print(1)", "language": "cobol", "themeID": "nope", "fontSize": "big", "future": 1,
             "highlightedLines": [2, 0]}
            """
        let decoded = try JSONDecoder().decode(CodeSnippet.self, from: Data(json.utf8))
        #expect(decoded.code == "print(1)")
        #expect(decoded.language == nil)
        #expect(decoded.fontSize == CodeSnippet.defaultFontSize)
        #expect(decoded.highlightedLines == [2])
        #expect(decoded.theme.id == CodeTheme.defaultID)
        #expect(CodeTheme.theme(id: "nope") == CodeTheme.theme(id: CodeTheme.defaultID))
    }

    @Test("[S11-AC8] normalisation: CRLF / CR become LF, tabs become four spaces")
    func normalisation() {
        #expect(CodeSnippet.normalize("a\r\nb\rc\td") == "a\nb\nc    d")
        #expect(CodeSnippetLayout.lines(of: "").count == 1)
        #expect(CodeSnippetLayout.lines(of: "a\n").count == 2)
        #expect(CodeSnippetLayout.lines(of: "a\nb\nc").count == 3)
    }

    @Test("[S11-AC2] reset style keeps code, language, title and highlighted lines")
    func resetStyle() {
        let snippet = CodeSnippet(
            code: "x", language: .go, showLineNumbers: false, highlightedLines: [1], title: "T", themeID: "ember",
            fontSize: 30, padding: 4, fontName: "Courier")
        let reset = snippet.resettingStyle()
        #expect(reset == CodeSnippet(code: "x", language: .go, highlightedLines: [1], title: "T"))
    }

    // MARK: Highlighted lines field

    @Test("[S11-AC11] parses lines and ranges; rejects invalid text; formats back with en dashes")
    func highlightedLines() {
        #expect(HighlightedLines.parse("2, 4-6") == [2, 4, 5, 6])
        #expect(HighlightedLines.parse("4–5 9") == [4, 5, 9])
        #expect(HighlightedLines.parse("") == [])
        #expect(HighlightedLines.parse("  ") == [])
        for invalid in ["abc", "0", "6-4", "1-", "-2", "1-2-3", "1-99999"] {
            #expect(HighlightedLines.parse(invalid) == nil, "\(invalid)")
        }
        #expect(HighlightedLines.format([2, 4, 5, 6]) == "2, 4–6")
        #expect(HighlightedLines.format([1, 3]) == "1, 3")
        #expect(HighlightedLines.format([]) == "")
        #expect(HighlightedLines.format([7, 8]) == "7–8")
    }

    // MARK: Layout maths

    private let metrics = CodeFontMetrics(advance: 9, ascent: 12, descent: 3)

    @Test("[S11-AC8] size = padding + gutter + longest line + padding by padding + title + lines × line height")
    func layoutSize() {
        let snippet = CodeSnippet(code: "", fontSize: 15, padding: 28)
        let layout = CodeSnippetLayout(
            snippet: snippet, lineWidths: Array(repeating: 300.5, count: 12), metrics: metrics)
        #expect(layout.lineHeight == 23)
        #expect(layout.gutterWidth == 2 * 9 + 23)
        #expect(layout.size == PixelSize(width: Int((56 + 41 + 300.5).rounded(.up)), height: 56 + 12 * 23))
        #expect(layout.textX == 28 + 41)
        #expect(layout.codeTop == 28)
        #expect(layout.lineBand(1) == LayoutRect(x: 0, y: 28 + 23, width: 398, height: 23))

        let short = CodeSnippetLayout(snippet: snippet, lineWidths: [10], metrics: metrics)
        #expect(short.size.width == 56 + 41 + 24 * 9)
        let empty = CodeSnippetLayout(snippet: snippet, lineWidths: [], metrics: metrics)
        #expect(empty.lineCount == 1)
        #expect(empty.size.height == 56 + 23)
    }

    @Test("[S11-AC10] gutter fits the widest number and disappears when line numbers are off")
    func gutter() {
        let on = CodeSnippet(showLineNumbers: true)
        let off = CodeSnippet(showLineNumbers: false)
        let lines = Array(repeating: 100.0, count: 12)
        let withNumbers = CodeSnippetLayout(snippet: on, lineWidths: lines, metrics: metrics)
        let without = CodeSnippetLayout(snippet: off, lineWidths: lines, metrics: metrics)
        #expect(without.gutterWidth == 0)
        #expect(withNumbers.size.width - without.size.width == Int(withNumbers.gutterWidth))
        #expect(withNumbers.numbersRight == withNumbers.textX - withNumbers.lineHeight)
        let thousand = CodeSnippetLayout(
            snippet: on, lineWidths: Array(repeating: 100, count: 1000), metrics: metrics)
        #expect(thousand.gutterWidth == 4 * 9 + 23)
    }

    @Test("[S11-AC12] title row adds round(fontSize × 2.4) only when the title is set")
    func titleRow() {
        let plain = CodeSnippetLayout(snippet: CodeSnippet(title: ""), lineWidths: [10], metrics: metrics)
        let titled = CodeSnippetLayout(snippet: CodeSnippet(title: "main.swift"), lineWidths: [10], metrics: metrics)
        #expect(plain.titleHeight == 0)
        #expect(titled.titleHeight == 36)
        #expect(titled.size.height - plain.size.height == 36)
        #expect(titled.codeTop == 28 + 36)
        #expect(titled.titleRect == LayoutRect(x: 28, y: 28, width: Double(titled.size.width) - 56, height: 36))
    }
}
