public import CoreGraphics
import CoreText
import Foundation
public import SunshotCore

/// Draws code-snippet content with CoreText. The result is the *content* image; backdrop, padding, border, shadow
/// and canvas size are applied afterwards by `Renderer` exactly as for an imported image.
///
/// The snippet is always drawn at the density it will be shown at (`scale`), so text stays sharp at 2×, 4K or an
/// exact canvas that scales the content up — it is never an upscaled 1× bitmap.
public enum CodeSnippetRenderer {
    /// Layout (and with it the content size at 1×) of `snippet`.
    public static func layout(of snippet: CodeSnippet) -> CodeSnippetLayout {
        PreparedSnippet(snippet, colored: false).layout
    }

    /// The snippet drawn at `scale` (pixel size = layout size × scale, rounded). Throws if the bitmap can't be made.
    public static func image(of snippet: CodeSnippet, scale: Double = 1) throws -> CGImage {
        try prepare(snippet).image(scale: scale)
    }

    /// Highlights and lays out once; `Renderer` uses the layout for the canvas and then draws at the density.
    static func prepare(_ snippet: CodeSnippet) -> PreparedSnippet { PreparedSnippet(snippet, colored: true) }

    /// The monospaced font for `snippet`: its `fontName` if installed, otherwise the default (Menlo).
    static func font(for snippet: CodeSnippet) -> CTFont {
        let size = CGFloat(snippet.fontSize)
        if let name = snippet.fontName {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            if CTFontCopyPostScriptName(font) as String == name { return font }
        }
        return CTFontCreateWithName(CodeSnippet.defaultFontName as CFString, size, nil)
    }

    static func metrics(of font: CTFont) -> CodeFontMetrics {
        var character: UniChar = 0x30  // "0"
        var glyph: CGGlyph = 0
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) {
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        }
        return CodeFontMetrics(
            advance: Double(advance.width), ascent: Double(CTFontGetAscent(font)),
            descent: Double(CTFontGetDescent(font)))
    }
}

/// Lines turned into CoreText lines plus the layout they produce. Built once per render.
struct PreparedSnippet {
    let snippet: CodeSnippet
    let theme: CodeTheme
    let font: CTFont
    let lines: [CTLine]
    let layout: CodeSnippetLayout

    init(_ snippet: CodeSnippet, colored: Bool) {
        self.snippet = snippet
        theme = snippet.theme
        font = CodeSnippetRenderer.font(for: snippet)
        let code = snippet.normalizedCode
        let tokens = colored ? SyntaxHighlighter.tokens(for: code, language: snippet.effectiveLanguage) : []
        var lines: [CTLine] = []
        var tokenIndex = 0
        var lineStart = 0
        for line in CodeSnippetLayout.lines(of: code) {
            let text = String(line)
            let length = text.utf16.count
            let attributed = NSMutableAttributedString(
                string: text, attributes: Self.attributes(font: font, color: theme.foreground))
            if colored {
                // Tokens are sorted; skip those that ended before this line, colour the overlapping part of the rest.
                while tokenIndex < tokens.count, tokens[tokenIndex].end <= lineStart { tokenIndex += 1 }
                var index = tokenIndex
                while index < tokens.count, tokens[index].start < lineStart + length {
                    let token = tokens[index]
                    let start = max(token.start, lineStart) - lineStart
                    let end = min(token.end, lineStart + length) - lineStart
                    attributed.addAttribute(
                        Self.colorKey, value: theme.color(for: token.kind).cgColor,
                        range: NSRange(location: start, length: end - start))
                    index += 1
                }
            }
            lines.append(CTLineCreateWithAttributedString(attributed))
            lineStart += length + 1
        }
        self.lines = lines
        let widths = lines.map { Double(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        layout = CodeSnippetLayout(
            snippet: snippet, lineWidths: widths, metrics: CodeSnippetRenderer.metrics(of: font))
    }

    static let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    static func attributes(font: CTFont, color: RGBAColor) -> [NSAttributedString.Key: Any] {
        [NSAttributedString.Key(kCTFontAttributeName as String): font, colorKey: color.cgColor]
    }

    /// The snippet drawn at `scale` (pixel size = layout size × scale, rounded).
    func image(scale: Double) throws -> CGImage {
        let size = layout.size
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let pixelWidth = max(1, ExportPlan.scaled(size.width, by: safeScale))
        let pixelHeight = max(1, ExportPlan.scaled(size.height, by: safeScale))
        guard let context = Renderer.makeContext(width: pixelWidth, height: pixelHeight) else {
            throw RenderError.contextCreationFailed
        }
        context.scaleBy(
            x: CGFloat(pixelWidth) / CGFloat(size.width), y: CGFloat(pixelHeight) / CGFloat(size.height))
        draw(in: context)
        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }

    /// Draws into a y-up context whose user space is the layout size.
    func draw(in context: CGContext) {
        let height = Double(layout.size.height)
        let width = Double(layout.size.width)
        context.setFillColor(theme.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(theme.highlight.cgColor)
        for line in snippet.highlightedLines.sorted() where line <= lines.count {
            let band = layout.lineBand(line - 1)
            context.fill(CGRect(x: band.x, y: height - band.y - band.height, width: band.width, height: band.height))
        }

        context.textMatrix = .identity
        context.setShouldSmoothFonts(false)
        drawTitle(in: context, height: height)
        let numberAttributes = Self.attributes(font: font, color: theme.lineNumber)
        for (index, line) in lines.enumerated() {
            let baseline = height - (layout.codeTop + Double(index) * layout.lineHeight + layout.baselineOffset)
            if layout.gutterWidth > 0 {
                let number = CTLineCreateWithAttributedString(
                    NSAttributedString(string: String(index + 1), attributes: numberAttributes))
                let numberWidth = CTLineGetTypographicBounds(number, nil, nil, nil)
                context.textPosition = CGPoint(x: layout.numbersRight - numberWidth, y: baseline)
                CTLineDraw(number, context)
            }
            context.textPosition = CGPoint(x: layout.textX, y: baseline)
            CTLineDraw(line, context)
        }
    }

    private func drawTitle(in context: CGContext, height: Double) {
        guard layout.titleHeight > 0 else { return }
        let titleFont = CTFontCreateUIFontForLanguage(.system, CGFloat(snippet.fontSize), nil) ?? font
        let attributes = Self.attributes(font: titleFont, color: theme.title)
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: snippet.title, attributes: attributes))
        let rect = layout.titleRect
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let line = CTLineCreateTruncatedLine(full, rect.width, .end, ellipsis) ?? ellipsis
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let baselineFromTop = rect.y + (rect.height - Double(ascent + descent)) / 2 + Double(ascent)
        context.textPosition = CGPoint(x: rect.x + (rect.width - lineWidth) / 2, y: height - baselineFromTop)
        CTLineDraw(line, context)
    }
}
