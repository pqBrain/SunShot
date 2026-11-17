import Foundation
import Testing

@testable import SunshotCore

@Suite("Annotation geometry and mapping")
struct AnnotationGeometryTests {
    private func point(_ x: Double, _ y: Double) -> AnnotationPoint { AnnotationPoint(x: x, y: y) }

    private func close(_ a: AnnotationPoint, _ b: AnnotationPoint, _ tolerance: Double = 1e-6) -> Bool {
        a.distance(to: b) <= tolerance
    }

    @Test("[S9-AC16] hit-testing per kind, with tolerance and rotation")
    func hitTesting() {
        let pen = Annotation(kind: .pen, points: [point(0, 0), point(100, 0)], lineWidth: 6)
        #expect(pen.contains(point(50, 4), tolerance: 2))
        #expect(!pen.contains(point(50, 8), tolerance: 2))
        let dot = Annotation(kind: .pen, points: [point(10, 10)], lineWidth: 6)
        #expect(dot.contains(point(12, 10), tolerance: 0))
        let arrow = Annotation(kind: .arrow, points: [point(0, 0), point(0, 100)], lineWidth: 4)
        #expect(arrow.contains(point(7, 50), tolerance: 0), "head length 16 → reach 8")
        let outline = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 50)], lineWidth: 4)
        #expect(outline.contains(point(1, 25), tolerance: 2))
        #expect(!outline.contains(point(50, 25), tolerance: 2), "outline rectangles are hit on their edges")
        var filled = outline
        filled.filled = true
        #expect(filled.contains(point(50, 25), tolerance: 0))
        let step = Annotation(kind: .step, points: [point(0, 0), point(40, 40)])
        #expect(step.contains(point(20, 20), tolerance: 0))
        #expect(!step.contains(point(1, 1), tolerance: 0), "steps are round")
        // A 100×10 bar rotated 90° about its centre (50, 5) stands upright: x 45…55, y −45…55.
        let bar = Annotation(kind: .sticker, points: [point(0, 0), point(100, 10)], rotation: 90)
        #expect(bar.contains(point(50, 40), tolerance: 0))
        #expect(!bar.contains(point(90, 5), tolerance: 0))
        #expect(Annotation(kind: .pen, points: []).bounds.width == 0)
        #expect(AnnotationGeometry.distance(from: point(1, 1), toPolyline: []) == .infinity)
        #expect(AnnotationGeometry.distance(from: point(3, 4), toSegment: point(0, 0), point(0, 0)) == 5)
    }

    @Test("[S9-AC16] the topmost annotation wins; ids(at:) finds all")
    func topmost() {
        let below = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 100)], filled: true)
        let above = Annotation(kind: .rectangle, points: [point(50, 50), point(150, 150)], filled: true)
        let layer = AnnotationLayer(items: [below, above])
        #expect(layer.topmost(at: point(75, 75), tolerance: 0)?.id == above.id)
        #expect(layer.topmost(at: point(10, 10), tolerance: 0)?.id == below.id)
        #expect(layer.topmost(at: point(200, 200), tolerance: 0) == nil)
        #expect(layer.ids(at: point(75, 75), tolerance: 0) == [below.id, above.id])
        #expect(layer.existing([below.id, UUID()]) == [below.id])
    }

    @Test("[S9-AC17] corner resize keeps the opposite corner fixed, also when rotated")
    func resize() {
        let rect = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 50)])
        let bigger = rect.resized(corner: .bottomRight, to: point(200, 150))
        #expect(bigger.bounds == LayoutRect(x: 0, y: 0, width: 200, height: 150))
        let flipped = rect.resized(corner: .bottomRight, to: point(-50, -20))
        #expect(flipped.bounds == LayoutRect(x: -50, y: -20, width: 50, height: 20))
        let tiny = rect.resized(corner: .topLeft, to: point(100, 50))
        #expect(tiny.bounds.width == AnnotationGeometry.minimumSize)

        var rotated = rect
        rotated.rotation = 30
        let anchorBefore = rotated.worldPoint(point(0, 0))
        let resized = rotated.resized(corner: .bottomRight, to: rotated.worldPoint(point(160, 90)))
        let anchorAfter = resized.worldPoint(point(resized.bounds.x, resized.bounds.y))
        #expect(close(anchorBefore, anchorAfter, 1e-6))
        #expect(abs(resized.bounds.width - 160) < 1e-6)
        #expect(abs(resized.bounds.height - 90) < 1e-6)

        let sticker = Annotation(kind: .sticker, points: [point(0, 0), point(40, 40)], text: "⭐")
        let grown = sticker.resized(corner: .bottomRight, to: point(100, 60))
        #expect(grown.bounds.width == grown.bounds.height, "stickers keep their aspect")
        #expect(grown.bounds.width == 100)
        let text = Annotation(kind: .text, points: [point(0, 0), point(100, 30)], fontSize: 24)
        #expect(text.resized(corner: .bottomRight, to: point(200, 60)).fontSize == 48)
    }

    @Test("[S9-AC17] rotation follows the handle, snaps to 15° with shift, stays within ±180°")
    func rotation() {
        let center = point(0, 0)
        let quarter = Annotation.rotation(
            original: 0, center: center, start: point(0, -10), point: point(10, 0), snap: false)
        #expect(abs(quarter - 90) < 1e-9)
        let snapped = Annotation.rotation(
            original: 0, center: center, start: point(0, -10), point: point(10, -2), snap: true)
        #expect(snapped == 75)
        let wrapped = Annotation.rotation(
            original: 170, center: center, start: point(0, -10), point: point(10, 0), snap: false)
        #expect(abs(wrapped - -100) < 1e-9)
        let wrappedDown = Annotation.rotation(
            original: -170, center: center, start: point(10, 0), point: point(0, -10), snap: false)
        #expect(abs(wrappedDown - 100) < 1e-9)
        #expect(point(1, 0).rotated(by: 0, around: center) == point(1, 0))
        #expect(close(point(1, 0).rotated(by: 90, around: center), point(0, 1)))
    }

    @Test("[S9-AC9] arrows have endpoint handles; boxes have four corners and a rotate handle")
    func handles() {
        let arrow = Annotation(kind: .arrow, points: [point(0, 0), point(50, 50)])
        #expect(arrow.handles(rotateOffset: 10).map(\.handle) == [.endpoint(0), .endpoint(1)])
        #expect(arrow.handle(at: point(49, 50), tolerance: 3, rotateOffset: 10) == .endpoint(1))
        let rect = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 50)])
        let handles = rect.handles(rotateOffset: 20)
        #expect(handles.count == 5)
        #expect(rect.handle(at: point(50, -20), tolerance: 3, rotateOffset: 20) == .rotate)
        #expect(rect.handle(at: point(100, 50), tolerance: 3, rotateOffset: 20) == .corner(.bottomRight))
        #expect(rect.handle(at: point(50, 25), tolerance: 3, rotateOffset: 20) == nil)
        #expect(AnnotationCorner.allCases.map(\.opposite) == [.bottomRight, .bottomLeft, .topRight, .topLeft])
    }

    @Test("[S9-AC5] preview ↔ content mapping round-trips across padding, exact sizes and display size")
    func mapping() {
        let content = PixelSize(width: 1000, height: 600)
        var project = Project()
        let auto = ContentMapping(contentSize: content, project: project, viewWidth: 564, viewHeight: 364)
        // Auto canvas 1128×728 shown at half size: content origin (64, 64) → view (32, 32).
        let origin = auto.viewPoint(fromContent: point(0, 0))
        #expect(abs(origin.x - 32) < 1e-9 && abs(origin.y - 32) < 1e-9)
        #expect(close(auto.contentPoint(fromView: 32, 32), point(0, 0)))
        #expect(abs(auto.viewPerContent - 0.5) < 1e-9)
        #expect(abs(auto.contentLength(fromView: 6) - 12) < 1e-9)
        #expect(abs(auto.viewLength(fromContent: 12) - 6) < 1e-9)

        project.canvas = .exact(PixelSize(width: 1920, height: 1080))
        let exact = ContentMapping(contentSize: content, project: project, viewWidth: 960, viewHeight: 540)
        for sample in [point(0, 0), point(123.5, 456.25), point(1000, 600), point(-20, 700)] {
            let view = exact.viewPoint(fromContent: sample)
            #expect(close(exact.contentPoint(fromView: view.x, view.y), sample, 1e-3))
        }
        #expect(exact.isInsideContent(point(500, 300)))
        #expect(!exact.isInsideContent(point(-1, 300)))
        #expect(!exact.isInsideContent(point(500, 601)))
        #expect(exact.contentLongEdge == 1000)
        let fallback = ContentMapping(contentSize: content, project: Project(), viewWidth: 0, viewHeight: .nan)
        #expect(fallback.viewWidth == 1128 && fallback.viewHeight == 728)
    }

    @Test("[S9-AC4] canvas position = content origin + content point × style scale")
    func attachedToContent() {
        let content = PixelSize(width: 1000, height: 600)
        let anchor = point(100, 100)
        for padding in [64.0, 200.0] {
            let project = Project(padding: padding)
            let mapping = ContentMapping(
                contentSize: content, project: project, viewWidth: 1000 + padding * 2, viewHeight: 600 + padding * 2)
            let view = mapping.viewPoint(fromContent: anchor)
            #expect(abs(view.x - (padding + 100)) < 1e-9)
        }
    }
}
