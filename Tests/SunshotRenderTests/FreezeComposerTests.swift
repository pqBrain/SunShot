import CoreGraphics
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Freeze capture result")
struct FreezeComposerTests {
    // A 400×200 pixel "display" shown as 200×100 points (2× density).
    private func frozen() throws -> CGImage { try Fixtures.solid(width: 400, height: 200, red: 0, green: 0, blue: 1) }

    @Test("[S19-AC4] without marks the result is the crop at pixel density")
    func plainCrop() throws {
        let image = try FreezeComposer.compose(
            frozen: frozen(), displaySize: (200, 100), crop: LayoutRect(x: 20, y: 10, width: 50, height: 30), marks: [])
        #expect((image.width, image.height) == (100, 60))
    }

    @Test("[S19-AC4] marks land where they were drawn on the screen")
    func marked() throws {
        let box = Annotation(
            kind: .rectangle, points: [AnnotationPoint(x: 30, y: 20), AnnotationPoint(x: 60, y: 40)],
            color: RGBAColor(rgb: 0xFF0000), lineWidth: 4, filled: true)
        let image = try FreezeComposer.compose(
            frozen: frozen(), displaySize: (200, 100), crop: LayoutRect(x: 20, y: 10, width: 50, height: 40),
            marks: [box])
        #expect((image.width, image.height) == (100, 80))
        let pixels = try PixelBuffer(image)
        // Screen point (45, 30) is crop point (25, 20) = pixel (50, 40): inside the filled box, so red.
        let inside = pixels.pixel(x: 50, y: 40)
        #expect(inside[0] > 230 && inside[2] < 30)
        // Screen point (22, 12) is outside the box: still the blue screen.
        let outside = pixels.pixel(x: 4, y: 4)
        #expect(outside[2] > 230 && outside[0] < 30)
    }

    @Test("[S19-AC4] an empty area fails")
    func empty() throws {
        #expect(throws: FreezeComposerError.self) {
            try FreezeComposer.compose(
                frozen: frozen(), displaySize: (200, 100), crop: LayoutRect(x: 500, y: 500, width: 10, height: 10),
                marks: [])
        }
    }
}
