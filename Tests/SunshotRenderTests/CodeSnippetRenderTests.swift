import CoreGraphics
import CoreText
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Code snippet rendering")
struct CodeSnippetRenderTests {
    private func color(_ buffer: PixelBuffer, _ x: Int, _ y: Int) -> [Int] {
        buffer.pixel(x: x, y: y).map(Int.init)
    }

    private func bytes(_ color: RGBAColor) -> [Int] {
        [color.red, color.green, color.blue, color.alpha].map { Int(($0 * 255).rounded()) }
    }

    private func isNear(_ pixel: [Int], _ target: [Int], tolerance: Int = 6) -> Bool {
        zip(pixel, target).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// Pixels in `rows` × `columns` within tolerance of `target`.
    private func count(
        _ target: RGBAColor, in buffer: PixelBuffer, columns: Range<Int>? = nil, rows: Range<Int>? = nil
    ) -> Int {
        let wanted = bytes(target)
        var found = 0
        for y in rows ?? 0..<buffer.height {
            for x in columns ?? 0..<buffer.width where isNear(color(buffer, x, y), wanted) { found += 1 }
        }
        return found
    }

    @Test("[S11-AC8] measured size follows the formula with Menlo metrics")
    func measuredSize() {
        let line = String(repeating: "a", count: 40)
        let snippet = CodeSnippet(code: "\(line)\nb\nc", showLineNumbers: true)
        let font = CodeSnippetRenderer.font(for: snippet)
        let metrics = CodeSnippetRenderer.metrics(of: font)
        #expect(metrics.advance > 8 && metrics.advance < 10)
        let layout = CodeSnippetRenderer.layout(of: snippet)
        let expectedWidth = 28 * 2 + (2 * metrics.advance + 23) + 40 * metrics.advance
        #expect(abs(Double(layout.size.width) - expectedWidth) < 1.01)
        #expect(layout.size.height == 56 + 3 * 23)
        // Tabs count as four spaces.
        let tabbed = CodeSnippetRenderer.layout(of: CodeSnippet(code: "\tx"))
        let spaced = CodeSnippetRenderer.layout(of: CodeSnippet(code: "    x"))
        #expect(tabbed == spaced)
    }

    @Test("[S11-AC8] a missing font falls back to Menlo")
    func fontFallback() {
        let missing = CodeSnippet(fontName: "NoSuchFont-Regular")
        #expect(CTFontCopyPostScriptName(CodeSnippetRenderer.font(for: missing)) as String == "Menlo-Regular")
        let courier = CodeSnippet(fontName: "Courier")
        #expect(CTFontCopyPostScriptName(CodeSnippetRenderer.font(for: courier)) as String == "Courier")
    }

    @Test("[S11-AC9] default snippet in the light theme matches the snapshot and uses theme colours")
    func lightSnapshot() throws {
        let snippet = CodeSnippet()
        let image = try CodeSnippetRenderer.image(of: snippet, scale: 2)
        try assertSnapshot(image, named: "s11-snippet-daybreak-2x")
        let buffer = try PixelBuffer(image)
        let theme = snippet.theme
        #expect(color(buffer, 2, 2) == bytes(theme.background))
        #expect(count(theme.color(for: .keyword), in: buffer) > 20)
        #expect(count(theme.color(for: .string), in: buffer) > 20)
        #expect(count(theme.color(for: .comment), in: buffer) > 20)
    }

    @Test("[S11-AC9] dark theme without line numbers matches the snapshot")
    func darkSnapshot() throws {
        let snippet = CodeSnippet(showLineNumbers: false, themeID: "midnight")
        let image = try CodeSnippetRenderer.image(of: snippet, scale: 2)
        try assertSnapshot(image, named: "s11-snippet-midnight-no-numbers-2x")
        let buffer = try PixelBuffer(image)
        #expect(color(buffer, 2, 2) == bytes(snippet.theme.background))
        #expect(CodeSnippetRenderer.layout(of: snippet).gutterWidth == 0)
    }

    @Test("[S11-AC10] line numbers are drawn in the gutter in the line-number colour")
    func lineNumbers() throws {
        let code = (1...12).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let on = CodeSnippet(code: code, showLineNumbers: true)
        let off = CodeSnippet(code: code, showLineNumbers: false)
        let layoutOn = CodeSnippetRenderer.layout(of: on)
        let layoutOff = CodeSnippetRenderer.layout(of: off)
        #expect(abs(Double(layoutOn.size.width - layoutOff.size.width) - layoutOn.gutterWidth) <= 1)
        let buffer = try PixelBuffer(try CodeSnippetRenderer.image(of: on, scale: 2))
        let gutter = Int(layoutOn.padding * 2)..<Int(layoutOn.numbersRight * 2)
        #expect(count(on.theme.lineNumber, in: buffer, columns: gutter) > 20)
    }

    @Test("[S11-AC11] highlighted lines get a full-width band; lines past the end are ignored")
    func highlightBand() throws {
        let code = "a\nb\nc\nd"
        let snippet = CodeSnippet(code: code, highlightedLines: [2, 99])
        let layout = CodeSnippetRenderer.layout(of: snippet)
        let buffer = try PixelBuffer(try CodeSnippetRenderer.image(of: snippet))
        let band = layout.lineBand(1)
        let other = layout.lineBand(2)
        #expect(color(buffer, 1, Int(band.midY)) == bytes(snippet.theme.highlight))
        #expect(color(buffer, layout.size.width - 2, Int(band.midY)) == bytes(snippet.theme.highlight))
        #expect(color(buffer, 1, Int(other.midY)) == bytes(snippet.theme.background))
        let plain = try CodeSnippetRenderer.image(of: CodeSnippet(code: code, highlightedLines: [2]))
        #expect(try PixelBuffer(plain).bytes == buffer.bytes)
    }

    @Test("[S11-AC12] a title row is drawn above the code, long titles are truncated")
    func titleSnapshot() throws {
        let titled = CodeSnippet(title: "sunrise.swift", themeID: "porcelain")
        try assertSnapshot(try CodeSnippetRenderer.image(of: titled, scale: 2), named: "s11-snippet-title-2x")
        let long = CodeSnippet(code: "x", title: String(repeating: "A very long title ", count: 20))
        let layout = CodeSnippetRenderer.layout(of: long)
        let short = CodeSnippetRenderer.layout(of: CodeSnippet(code: "x", title: "T"))
        #expect(layout.size == short.size)
        let buffer = try PixelBuffer(try CodeSnippetRenderer.image(of: long))
        let title = layout.titleRect
        // Truncated text stays inside the padding: the outer padding columns are untouched background.
        let rows = Int(title.y)..<Int(title.y + title.height)
        #expect(count(long.theme.background, in: buffer, columns: 0..<Int(layout.padding) - 2, rows: rows) > 0)
        #expect(count(long.theme.title, in: buffer, columns: 0..<Int(layout.padding) - 2, rows: rows) == 0)
        #expect(count(long.theme.title, in: buffer, rows: rows) > 10)
    }

    @Test("[S11-AC13] the snippet flows through backdrop, padding, border, shadow and canvas size")
    func pipeline() throws {
        let project = Project(
            canvas: .ratio(16.0 / 9), backdrop: .gradient(SunshotDefaults.gradient), padding: 40,
            border: Border(style: .round, radius: 30), shadow: Shadow(style: .spread, intensity: .high))
        let snippet = CodeSnippet(title: "demo")
        let document = EditorDocument(project: project, snippet: snippet)
        let rendered = try #require(try Renderer.render(document: document))
        let viaImage = try Renderer.render(project: project, content: CodeSnippetRenderer.image(of: snippet))
        #expect(try PixelBuffer(rendered).bytes == PixelBuffer(viaImage).bytes)
        let contentSize = try #require(document.contentPixelSize)
        let expected = CanvasLayout.compute(contentSize: contentSize, project: project).canvasSize
        #expect((rendered.width, rendered.height) == (expected.width, expected.height))
    }

    @Test("[S11-AC14] export re-renders the code at the output density, not an upscaled 1× bitmap")
    func exportDensity() throws {
        let snippet = CodeSnippet()
        let project = Project()
        let document = EditorDocument(project: project, snippet: snippet)
        let size = CodeSnippetRenderer.layout(of: snippet).size
        let twoX = try #require(try Renderer.render(document: document, scale: 2))
        let sharp = try Renderer.render(
            project: project, content: CodeSnippetRenderer.image(of: snippet, scale: 2), contentSize: size, scale: 2)
        let upscaled = try Renderer.render(project: project, content: CodeSnippetRenderer.image(of: snippet), scale: 2)
        #expect(try PixelBuffer(twoX).bytes == PixelBuffer(sharp).bytes)
        #expect(try PixelBuffer(twoX).bytes != PixelBuffer(upscaled).bytes)
        #expect((twoX.width, twoX.height) == (upscaled.width, upscaled.height))

        // An exact canvas that scales the content up draws it at scale × styleScale.
        var exact = project
        exact.canvas = .exact(PixelSize(width: size.width * 3, height: size.height * 3))
        let layout = CanvasLayout.compute(contentSize: size, project: exact)
        #expect(layout.styleScale > 1.5)
        let density = Renderer.contentDensity(scale: 1, layout: layout)
        #expect(density == layout.styleScale)
        let exactRender = try #require(try Renderer.render(document: EditorDocument(project: exact, snippet: snippet)))
        let exactSharp = try Renderer.render(
            project: exact, content: CodeSnippetRenderer.image(of: snippet, scale: density), contentSize: size)
        #expect(try PixelBuffer(exactRender).bytes == PixelBuffer(exactSharp).bytes)
        #expect(Renderer.contentDensity(scale: .nan, layout: layout) == layout.styleScale)
    }
}
