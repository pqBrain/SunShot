import Testing

@testable import SunshotCore

@Suite("Canvas gestures")
struct CanvasGesturesTests {
    /// 400 × 300 canvas with 200 × 100 content in the middle.
    static let layout = CanvasLayout(
        canvasSize: PixelSize(width: 400, height: 300), contentRect: LayoutRect(x: 100, y: 100, width: 200, height: 100)
    )

    @Test("[S6-AC21] the screenshot is hit where it is drawn; the backdrop around it is not")
    func hitTestFlat() {
        let identity = ContentTransform.identity
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 200, y: 150), layout: Self.layout, transform: identity) == .content)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 101, y: 101), layout: Self.layout, transform: identity) == .content)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 99, y: 150), layout: Self.layout, transform: identity) == .backdrop)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 10, y: 10), layout: Self.layout, transform: identity) == .backdrop)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: .nan, y: 150), layout: Self.layout, transform: identity)
                == .backdrop)
    }

    @Test("[S6-AC21] moved, zoomed and rotated content is hit at its new place")
    func hitTestTransformed() {
        let moved = ContentTransform(x: 0.25)  // +100 px
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 350, y: 150), layout: Self.layout, transform: moved) == .content)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 150, y: 150), layout: Self.layout, transform: moved) == .backdrop)
        let rotated = ContentTransform(rotation: 90)  // 100 wide × 200 tall about (200, 150)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 200, y: 60), layout: Self.layout, transform: rotated) == .content)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 280, y: 150), layout: Self.layout, transform: rotated) == .backdrop)
        let zoomed = ContentTransform(zoom: 50)  // 100 × 50 about the centre
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 110, y: 150), layout: Self.layout, transform: zoomed) == .backdrop)
        let tilted = ContentTransform(tiltY: 40)
        #expect(
            CanvasHitTest.region(at: LayoutPoint(x: 200, y: 150), layout: Self.layout, transform: tilted) == .content)
        #expect(CanvasHitTest.quad(layout: Self.layout, transform: tilted).count == 4)
    }

    @Test("[S6-AC21] frame chrome counts as the screenshot")
    func hitTestFrameChrome() {
        let framed = CanvasLayout(
            canvasSize: PixelSize(width: 400, height: 300),
            contentRect: LayoutRect(x: 100, y: 120, width: 200, height: 80),
            frameRect: LayoutRect(x: 100, y: 100, width: 200, height: 100))
        #expect(CanvasHitTest.region(at: LayoutPoint(x: 200, y: 110), layout: framed, transform: .identity) == .content)
        #expect(CanvasHitTest.region(at: LayoutPoint(x: 200, y: 95), layout: framed, transform: .identity) == .backdrop)
        #expect(!CanvasHitTest.contains([LayoutPoint(x: 0, y: 0)], LayoutPoint(x: 0, y: 0)))
    }

    @Test("[S6-AC22] pinch scales from the start zoom, whole percent, clamped")
    func pinch() {
        let pinch = CanvasPinch(startZoom: 100)
        #expect(pinch.zoom(magnification: 1.5) == 150)
        #expect(pinch.zoom(magnification: 1.234) == 123)
        #expect(pinch.zoom(magnification: 10) == 400)
        #expect(pinch.zoom(magnification: 0.1) == 25)
        #expect(pinch.zoom(magnification: 0) == 100)
        #expect(pinch.zoom(magnification: .infinity) == 100)
        #expect(CanvasPinch(startZoom: 200).zoom(magnification: 0.5) == 100)
    }

    @Test("[S6-AC22] twist adds the angle and snaps to multiples of 45° within 4°")
    func twist() {
        let twist = CanvasTwist(startRotation: 0)
        #expect(twist.rotation(angle: 20) == 20)
        #expect(twist.rotation(angle: 42) == 45)
        #expect(twist.rotation(angle: 42, snaps: false) == 42)
        #expect(twist.rotation(angle: -3) == 0)
        #expect(twist.rotation(angle: .nan) == 0)
        #expect(CanvasTwist(startRotation: 170).rotation(angle: 30) == -160)
        #expect(CanvasTwist(startRotation: 170).rotation(angle: 12) == 180)
    }

    @Test("[S6-AC24] the preview renders at the displayed size (128 px steps), never above the max side")
    func previewSizing() {
        let canvas = PixelSize(width: 800, height: 600)
        #expect(PreviewSizing.scale(canvas: canvas, displayPixels: nil) == 1)
        // Display smaller than the canvas: rendered at the displayed size (long side 400 → 512 after quantising),
        // not at full canvas resolution.
        #expect(PreviewSizing.scale(canvas: canvas, displayPixels: (400, 300)) == 512 / 800.0)
        // Never below one 128 px step on the long side, however small the display.
        #expect(PreviewSizing.scale(canvas: canvas, displayPixels: (1, 1)) == 128 / 800.0)
        // Display 2000 × 1200: fits by height (2×), quantised up to a 128 px step on the long side.
        let scale = PreviewSizing.scale(canvas: canvas, displayPixels: (2000, 1200))
        #expect(scale >= 2 && scale < 2 + 128 / 800.0)
        #expect(PreviewSizing.scale(canvas: canvas, displayPixels: (.nan, 100)) == 1)
        let huge = PixelSize(width: 12288, height: 100)
        #expect(PreviewSizing.scale(canvas: huge, displayPixels: (99999, 99999)) == 0.5)
        let tiny = PixelSize(width: 10, height: 10)
        #expect(
            PreviewSizing.scale(canvas: tiny, displayPixels: (1e9, 1e9)) == Double(SunshotDefaults.previewMaxSide) / 10)
    }
}

@Suite("Canvas drags")
struct CanvasDragsTests {
    @Test("[S6-AC25] dragging away from the screenshot grows the padding, toward it shrinks, clamped")
    func paddingDrag() {
        // Pressed left of the screenshot: moving left is outward.
        let drag = PaddingDrag(startPadding: 64, pixelsPerPoint: 2, pressX: -100, pressY: 0)
        #expect(drag.padding(translationX: -10, translationY: 0) == 84)
        #expect(drag.padding(translationX: 10, translationY: 50) == 44)
        #expect(drag.padding(translationX: 1000, translationY: 0) == 0)
        #expect(drag.padding(translationX: -5000, translationY: 0) == SunshotDefaults.maxPadding)
        #expect(drag.padding(translationX: .nan, translationY: 0) == 64)
        let centre = PaddingDrag(startPadding: 10, pixelsPerPoint: .nan, pressX: 0, pressY: 0)
        #expect(centre.padding(translationX: 3, translationY: -1) == 13)
        #expect(centre.padding(translationX: 1, translationY: 6) == 16)
        #expect(PaddingDrag(startPadding: .infinity, pixelsPerPoint: 1, pressX: 1, pressY: 0).startPadding == 64)
    }

    @Test("[S6-AC26] ⇧-drag tilts like the Tilt pad: right leans the right side away, up leans the top away")
    func tiltDrag() {
        let drag = TiltDrag(start: ContentTransform())
        let right = drag.tilt(translationX: 200, translationY: 0)
        #expect(right.tiltY == TiltPad.edgeTilt && right.tiltX == 0)
        let up = drag.tilt(translationX: 0, translationY: -100)
        #expect(up.tiltX == 15 && up.tiltY == 0)
        let far = drag.tilt(translationX: -9999, translationY: .nan)
        #expect(far.tiltY == -60 && far.tiltX == 0)
        #expect(TiltDrag(start: ContentTransform(tiltX: 10)).tilt(translationX: 0, translationY: 0).tiltX == 10)
    }

    @Test("[S6-AC27] the corner handle sits radius in from the corner and dragging it sets the radius")
    func cornerHandle() {
        #expect(CornerRadiusHandle.inset(radius: 24, pointsPerPixel: 2) == 48)
        #expect(CornerRadiusHandle.inset(radius: 2, pointsPerPixel: 1) == CornerRadiusHandle.minimumInset)
        #expect(CornerRadiusHandle.inset(radius: .nan, pointsPerPixel: .nan) == CornerRadiusHandle.minimumInset)
        #expect(CornerRadiusHandle.radius(start: 24, translationX: 10, translationY: 10, pointsPerPixel: 2) == 29)
        #expect(CornerRadiusHandle.radius(start: 24, translationX: -500, translationY: -500, pointsPerPixel: 1) == 0)
        #expect(CornerRadiusHandle.radius(start: 24, translationX: .nan, translationY: 4, pointsPerPixel: 0) == 26)
        #expect(CornerRadiusHandle.radius(start: 190, translationX: 50, translationY: 50, pointsPerPixel: 1) == 200)
    }

    @Test("[S6-AC25] the quad centre is the mean of its corners")
    func centre() {
        let quad = [LayoutPoint(x: 0, y: 0), LayoutPoint(x: 4, y: 0), LayoutPoint(x: 4, y: 2), LayoutPoint(x: 0, y: 2)]
        #expect(CanvasHitTest.centre(of: quad) == LayoutPoint(x: 2, y: 1))
        #expect(CanvasHitTest.centre(of: []) == LayoutPoint(x: 0, y: 0))
    }
}
