import Testing

@testable import SunshotCore

@Suite("CanvasLayout")
struct CanvasLayoutTests {
    private let content = PixelSize(width: 1000, height: 500)

    @Test("[S0] auto canvas adds padding on every side and centres content")
    func autoCanvas() {
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .auto, padding: 0.1))
        #expect(layout.canvasSize == PixelSize(width: 1200, height: 700))
        #expect(layout.contentRect == LayoutRect(x: 100, y: 100, width: 1000, height: 500))
    }

    @Test(
        "[S0] ratio canvas is the smallest canvas of that ratio that fits",
        arguments: [1.0, 16.0 / 9.0, 9.0 / 16.0, 3.0])
    func ratioCanvas(ratio: Double) {
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .ratio(ratio), padding: 0.1))
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
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .exact(canvas), padding: 0.1))
        #expect(layout.canvasSize == canvas)
        #expect(abs(layout.contentRect.width - 1290.0 * 1000 / 1200) < 0.001)
        #expect(abs(layout.contentRect.midY - 1398) < 0.001)
    }

    @Test("[S0] padding is clamped to 0...0.5 and pixel sizes to at least 1")
    func clamping() {
        #expect(Project(padding: 9).padding == 0.5)
        #expect(Project(padding: -1).padding == 0)
        #expect(PixelSize(width: 0, height: -5) == PixelSize(width: 1, height: 1))
    }
}
