import Foundation
import SunshotCore
import Testing

@Suite("Crop geometry")
struct CropGeometryTests {
    private let image = PixelSize(width: 1000, height: 600)
    private let start = LayoutRect(x: 100, y: 100, width: 400, height: 300)

    private func inside(_ rect: LayoutRect, _ size: PixelSize = PixelSize(width: 1000, height: 600)) -> Bool {
        rect.x >= -1e-9 && rect.y >= -1e-9 && rect.x + rect.width <= Double(size.width) + 1e-9
            && rect.y + rect.height <= Double(size.height) + 1e-9
    }

    @Test("[S10-AC1] crops are clamped to the image; nothing left is nil")
    func clamping() {
        #expect(
            CropRect(x: -20, y: -10, width: 300, height: 200).clamped(to: image)
                == CropRect(x: 0, y: 0, width: 280, height: 190))
        #expect(
            CropRect(x: 900, y: 500, width: 300, height: 300).clamped(to: image)
                == CropRect(x: 900, y: 500, width: 100, height: 100))
        #expect(CropRect(x: 2000, y: 0, width: 10, height: 10).clamped(to: image) == nil)
        #expect(CropRect(x: 10, y: 10, width: -5, height: 10).clamped(to: image) == nil)
        #expect(CropRect(full: image).isFull(of: image))
        #expect(!CropRect(x: 1, y: 0, width: 999, height: 600).isFull(of: image))
        #expect(CropRect(full: image).size == image)
        #expect(CropRect(x: 1, y: 2, width: 3, height: 4).layoutRect == LayoutRect(x: 1, y: 2, width: 3, height: 4))
    }

    @Test("[S10-AC1] fractional rects round to whole pixels inside the image, at least 1×1")
    func rounding() {
        let rounded = CropRect.rounded(LayoutRect(x: 10.4, y: 20.6, width: 99.8, height: 50.2), in: image)
        #expect(rounded == CropRect(x: 10, y: 21, width: 100, height: 50))
        #expect(
            CropRect.rounded(LayoutRect(x: 990, y: 590, width: 50, height: 50), in: image)
                == CropRect(x: 990, y: 590, width: 10, height: 10))
        #expect(
            CropRect.rounded(LayoutRect(x: .nan, y: 0, width: 0.2, height: 0.2), in: image) == CropRect(full: image))
    }

    @Test("[S10-AC2] free handle drags move only their edges, stay inside, never flip, keep 16 px")
    func freeDrags() {
        for handle in CropHandle.allCases where handle != .move {
            for (dx, dy) in [(37.0, -23.0), (-5000.0, -5000.0), (5000.0, 5000.0), (-390.0, 290.0), (.nan, 1)] {
                let rect = CropGeometry.drag(handle, from: start, dx: dx, dy: dy, ratio: nil, imageSize: image)
                #expect(inside(rect), "\(handle) \(dx),\(dy) → \(rect)")
                #expect(rect.width >= CropGeometry.minimumSide - 1e-9 && rect.height >= CropGeometry.minimumSide - 1e-9)
            }
        }
        let right = CropGeometry.drag(.right, from: start, dx: 50, dy: 80, ratio: nil, imageSize: image)
        #expect(right == LayoutRect(x: 100, y: 100, width: 450, height: 300))
        let topLeft = CropGeometry.drag(.topLeft, from: start, dx: -30, dy: 20, ratio: nil, imageSize: image)
        #expect(topLeft == LayoutRect(x: 70, y: 120, width: 430, height: 280))
        // Past the opposite edge: stops 16 px short instead of flipping.
        let crossed = CropGeometry.drag(.left, from: start, dx: 1000, dy: 0, ratio: nil, imageSize: image)
        #expect(crossed.x == 500 - CropGeometry.minimumSide && crossed.width == CropGeometry.minimumSide)
        let bottom = CropGeometry.drag(.bottom, from: start, dx: 0, dy: 1000, ratio: nil, imageSize: image)
        #expect(bottom == LayoutRect(x: 100, y: 100, width: 400, height: 500))
    }

    @Test("[S10-AC2] dragging the interior moves without resizing and stops at the edges")
    func moveDrag() {
        let moved = CropGeometry.drag(.move, from: start, dx: 50, dy: -40, ratio: nil, imageSize: image)
        #expect(moved == LayoutRect(x: 150, y: 60, width: 400, height: 300))
        let pinned = CropGeometry.drag(.move, from: start, dx: 5000, dy: 5000, ratio: 1, imageSize: image)
        #expect(pinned == LayoutRect(x: 600, y: 300, width: 400, height: 300))
        let pinnedOrigin = CropGeometry.drag(.move, from: start, dx: -5000, dy: -5000, ratio: nil, imageSize: image)
        #expect(pinnedOrigin == LayoutRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test("[S10-AC3] a ratio preset gives the largest centred rect of that ratio inside the crop")
    func presets() {
        let full = CropRect(full: image).layoutRect
        let square = CropGeometry.fit(ratio: CropAspect.square.ratio(for: image), inside: full)
        #expect(square == LayoutRect(x: 200, y: 0, width: 600, height: 600))
        let wide = CropGeometry.fit(ratio: CropAspect.wide16x9.ratio(for: image), inside: full)
        #expect(wide.width == 1000 && abs(wide.height - 562.5) < 1e-9 && abs(wide.y - 18.75) < 1e-9)
        #expect(CropGeometry.fit(ratio: nil, inside: start) == start)
        #expect(CropAspect.free.ratio(for: image) == nil)
        #expect(CropAspect.original.ratio(for: image) == image.aspectRatio)
        let expected: [CropAspect: Double] = [
            .landscape4x3: 4.0 / 3, .portrait3x4: 0.75, .landscape3x2: 1.5, .portrait2x3: 2.0 / 3, .tall9x16: 9.0 / 16,
        ]
        for (aspect, ratio) in expected {
            let rect = CropGeometry.fit(ratio: aspect.ratio(for: image), inside: start)
            #expect(abs(rect.width / rect.height - ratio) < 1e-9)
            #expect(abs(rect.midX - start.midX) < 1e-9 && abs(rect.midY - start.midY) < 1e-9)
            #expect(rect.width <= start.width + 1e-9 && rect.height <= start.height + 1e-9)
        }
    }

    @Test("[S10-AC3] ratio-locked drags keep the ratio, the image bounds and the anchor")
    func ratioDrags() {
        let ratio = 4.0 / 3.0
        let locked = CropGeometry.fit(ratio: ratio, inside: start)
        for handle in CropHandle.allCases where handle != .move {
            for (dx, dy) in [(60.0, 10.0), (-30.0, -90.0), (5000.0, 5000.0), (-5000.0, -5000.0), (-380.0, 0.0)] {
                let rect = CropGeometry.drag(handle, from: locked, dx: dx, dy: dy, ratio: ratio, imageSize: image)
                #expect(abs(rect.width / rect.height - ratio) < 0.01, "\(handle) \(dx),\(dy) → \(rect)")
                #expect(inside(rect), "\(handle) \(dx),\(dy) → \(rect)")
                #expect(rect.height >= CropGeometry.minimumSide - 1e-9)
            }
        }
        // The bottom-right corner is anchored at the top-left corner.
        let corner = CropGeometry.drag(.bottomRight, from: locked, dx: 40, dy: 0, ratio: ratio, imageSize: image)
        #expect(corner.x == locked.x && corner.y == locked.y && abs(corner.width - (locked.width + 40)) < 1e-9)
        // The right edge is anchored at the left edge, centred vertically.
        let edge = CropGeometry.drag(.right, from: locked, dx: 40, dy: 0, ratio: ratio, imageSize: image)
        #expect(edge.x == locked.x && abs(edge.midY - locked.midY) < 1e-9)
        // The top edge is anchored at the bottom edge, centred horizontally.
        let top = CropGeometry.drag(.top, from: locked, dx: 0, dy: -30, ratio: ratio, imageSize: image)
        #expect(abs(top.y + top.height - (locked.y + locked.height)) < 1e-9 && abs(top.midX - locked.midX) < 1e-9)
    }

    @Test("[S10-AC4] hit-testing: corners, then edges, then the interior; nothing outside")
    func hitTesting() {
        let rect = start
        func handle(_ x: Double, _ y: Double) -> CropHandle? {
            CropGeometry.handle(at: AnnotationPoint(x: x, y: y), in: rect, tolerance: 8)
        }
        #expect(handle(102, 97) == .topLeft)
        #expect(handle(498, 104) == .topRight)
        #expect(handle(95, 403) == .bottomLeft)
        #expect(handle(505, 395) == .bottomRight)
        #expect(handle(300, 96) == .top)
        #expect(handle(300, 404) == .bottom)
        #expect(handle(94, 250) == .left)
        #expect(handle(506, 250) == .right)
        #expect(handle(300, 250) == .move)
        #expect(handle(50, 250) == nil)
        #expect(handle(300, 450) == nil)
    }

    @Test("[S10-AC8] the dialog fits ordinary images and scrolls tall ones at full width")
    func display() {
        let fitted = CropDisplay(imageSize: image, maxWidth: 720, maxHeight: 520)
        #expect(!fitted.scrolls && abs(fitted.scale - 0.72) < 1e-9)
        let tall = CropDisplay(imageSize: PixelSize(width: 1440, height: 16000), maxWidth: 720, maxHeight: 520)
        #expect(tall.scrolls && tall.scale == 0.5)
        let small = CropDisplay(imageSize: PixelSize(width: 200, height: 100), maxWidth: 720, maxHeight: 520)
        #expect(!small.scrolls && small.scale == 1)
        let portrait = CropDisplay(imageSize: PixelSize(width: 600, height: 1000), maxWidth: 720, maxHeight: 520)
        #expect(!portrait.scrolls && abs(portrait.scale - 0.52) < 1e-9)
        let point = tall.contentPoint(x: 100, y: 250)
        #expect(point == AnnotationPoint(x: 200, y: 500))
        #expect(
            tall.viewRect(LayoutRect(x: 200, y: 500, width: 40, height: 20))
                == LayoutRect(x: 100, y: 250, width: 20, height: 10))
        let fallback = CropDisplay(imageSize: image, maxWidth: .nan, maxHeight: 0)
        #expect(fallback.scale == 1)
    }

    @Test("[S10-AC9] shifting an annotation layer moves every annotation; zero offset is identity")
    func shiftedLayer() {
        var layer = AnnotationLayer()
        layer.add(
            Annotation(kind: .rectangle, points: [AnnotationPoint(x: 300, y: 200), AnnotationPoint(x: 400, y: 280)]))
        let shifted = layer.shifted(by: AnnotationPoint(x: -200, y: -100))
        #expect(shifted.items.first?.points == [AnnotationPoint(x: 100, y: 100), AnnotationPoint(x: 200, y: 180)])
        #expect(layer.shifted(by: AnnotationPoint(x: 0, y: 0)) == layer)
    }

    @Test("[S10-AC9] annotation pointer mapping adds the crop origin and back")
    func mappingWithOrigin() {
        let project = Project.plain(padding: 0)
        let mapping = ContentMapping(
            contentSize: PixelSize(width: 400, height: 300), project: project, viewWidth: 400, viewHeight: 300,
            origin: AnnotationPoint(x: 200, y: 100))
        #expect(mapping.contentPoint(fromView: 10, 20) == AnnotationPoint(x: 210, y: 120))
        let view = mapping.viewPoint(fromContent: AnnotationPoint(x: 210, y: 120))
        #expect(view.x == 10 && view.y == 20)
        #expect(mapping.isInsideContent(AnnotationPoint(x: 590, y: 390)))
        #expect(!mapping.isInsideContent(AnnotationPoint(x: 150, y: 150)))
    }
}
