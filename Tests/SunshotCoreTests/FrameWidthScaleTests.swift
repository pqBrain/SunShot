import SunshotCore
import Testing

@Suite("S17 frame chrome scales with the content width")
struct FrameWidthScaleTests {
    @Test(
        "[S17-AC10] chrome keeps its size up to 1440 px of content, then grows in proportion; UI scale applies on top")
    func chromeGrowsWithWidth() {
        let mac = Frame(kind: .macWindow)
        #expect(FrameGeometry.insets(for: mac, contentWidth: 800).top == 28)
        #expect(FrameGeometry.insets(for: mac, contentWidth: 1440).top == 28)
        #expect(FrameGeometry.insets(for: mac, contentWidth: 2880).top == 56, "a Retina capture: twice as tall")
        #expect(FrameGeometry.insets(for: Frame(kind: .browserWindow), contentWidth: 2880).top == 88)
        #expect(FrameGeometry.insets(for: Frame(kind: .macWindow, uiScale: 50), contentWidth: 2880).top == 28)
        #expect(FrameGeometry.insets(for: Frame(kind: .card), contentWidth: 2880).left == 48)
        #expect(FrameMetrics.widthScale(contentWidth: .nan) == 1)
    }

    @Test("[S17-AC10] the geometry of a frame box finds the same content width and chrome as the layout")
    func geometryMatchesLayout() {
        for kind in FrameKind.allCases {
            for width in [300.0, 1440, 2000, 2880, 6000] {
                let frame = Frame(kind: kind)
                let insets = FrameGeometry.insets(for: frame, contentWidth: width)
                let boxWidth = width + insets.horizontal
                let found = FrameGeometry.contentWidth(boxWidth: boxWidth, frame: frame)
                #expect(abs(found - width) < 0.001, "\(kind) \(width)")
                let geometry = FrameGeometry(frame: frame, boxWidth: boxWidth, boxHeight: 900 + insets.vertical)
                #expect(abs(geometry.content.width - width) < 0.001, "\(kind) \(width)")
                #expect(abs(geometry.content.y - insets.top) < 0.001, "\(kind) \(width)")
            }
        }
    }
}
