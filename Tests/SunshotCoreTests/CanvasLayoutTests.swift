import Testing

@testable import SunshotCore

@Suite("CanvasLayout")
struct CanvasLayoutTests {
    private let content = PixelSize(width: 1000, height: 500)

    @Test("[S0] auto canvas adds padding on every side and centres content")
    func autoCanvas() {
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .auto, padding: 100))
        #expect(layout.canvasSize == PixelSize(width: 1200, height: 700))
        #expect(layout.contentRect == LayoutRect(x: 100, y: 100, width: 1000, height: 500))
    }

    @Test(
        "[S1-AC7] default padding is 64 px on all four sides for any content size",
        arguments: [
            (PixelSize(width: 1, height: 1), PixelSize(width: 129, height: 129)),
            (PixelSize(width: 16, height: 16), PixelSize(width: 144, height: 144)),
            (PixelSize(width: 1000, height: 600), PixelSize(width: 1128, height: 728)),
            (PixelSize(width: 600, height: 1000), PixelSize(width: 728, height: 1128)),
            (PixelSize(width: 8000, height: 8000), PixelSize(width: 8128, height: 8128)),
        ])
    func defaultPadding(content: PixelSize, expected: PixelSize) {
        let layout = CanvasLayout.compute(contentSize: content, project: Project())
        #expect(layout.canvasSize == expected)
        let rect = layout.contentRect
        #expect(rect.x == 64 && rect.y == 64)
        #expect(Double(expected.width) - rect.x - rect.width == 64)
        #expect(Double(expected.height) - rect.y - rect.height == 64)
    }

    @Test(
        "[S0] ratio canvas is the smallest canvas of that ratio that fits",
        arguments: [1.0, 16.0 / 9.0, 9.0 / 16.0, 3.0])
    func ratioCanvas(ratio: Double) {
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .ratio(ratio), padding: 100))
        #expect(abs(layout.canvasSize.aspectRatio - ratio) < 0.01)
        #expect(layout.canvasSize.width >= 1200)
        #expect(layout.canvasSize.height >= 700)
        #expect(layout.contentRect.width == 1000)
        #expect(abs(layout.contentRect.midX - Double(layout.canvasSize.width) / 2) < 0.5)
        #expect(abs(layout.contentRect.midY - Double(layout.canvasSize.height) / 2) < 0.5)
    }

    @Test("[S0] invalid ratios fall back to square", arguments: [0.0, -2.0, Double.nan, Double.infinity])
    func invalidRatio(ratio: Double) {
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .ratio(ratio), padding: 0))
        #expect(layout.canvasSize.width == layout.canvasSize.height)
    }

    @Test("[S0] exact canvas keeps its size and scales content to fit the padded area")
    func exactCanvas() {
        let canvas = PixelSize(width: 1290, height: 2796)
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .exact(canvas), padding: 45))
        #expect(layout.canvasSize == canvas)
        #expect(abs(layout.contentRect.width - 1200) < 0.001)
        #expect(abs(layout.contentRect.midY - 1398) < 0.001)
    }

    @Test("[S0] exact canvas smaller than the padding leaves an empty content rect")
    func exactCanvasTooSmall() {
        let layout = CanvasLayout.compute(
            contentSize: content, project: Project(canvas: .exact(PixelSize(width: 100, height: 100)), padding: 64))
        #expect(layout.contentRect.width == 0 && layout.contentRect.midX == 50)
    }

    @Test("[S1] padding is clamped to 0...maxPadding, non-finite falls back to default; pixel sizes ≥ 1")
    func clamping() {
        #expect(Project(padding: 1e9).padding == SunshotDefaults.maxPadding)
        #expect(Project(padding: -1).padding == 0)
        #expect(Project(padding: .nan).padding == SunshotDefaults.padding)
        #expect(PixelSize(width: 0, height: -5) == PixelSize(width: 1, height: 1))
    }
}
