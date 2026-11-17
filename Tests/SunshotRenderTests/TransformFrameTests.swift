import CoreGraphics
import SunshotCore
import Testing

@testable import SunshotRender

/// S6 × S5: the content transform carries the frame chrome with the content, as one object.
@Suite("Transform with frames")
struct TransformFrameTests {
    private static func framedProject(rotation: Double, shadow: Shadow = Shadow(style: .none)) -> Project {
        var project = Project(
            backdrop: .solid(RGBAColor(red: 1, green: 0, blue: 1)), padding: 200, border: Border(style: .sharp),
            shadow: shadow)
        project.frame = Frame(kind: .macWindow)
        project.placement.transform = ContentTransform(rotation: rotation)
        return project
    }

    /// Bounding box of every pixel that isn't the magenta backdrop.
    private static func silhouetteBounds(_ image: CGImage) throws -> (width: Int, height: Int) {
        let pixels = try PixelBuffer(image)
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
        for y in 0..<image.height {
            for x in 0..<image.width where pixels.pixel(x: x, y: y) != [255, 0, 255, 255] {
                (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
            }
        }
        return (maxX - minX + 1, maxY - minY + 1)
    }

    @Test("[S6-AC8] a 90° rotation turns the whole mac window (title bar included), not just the content")
    func frameRotatesWithContent() throws {
        let content = try Fixtures.solid(width: 400, height: 260)
        let upright = try Self.silhouetteBounds(
            try Renderer.render(project: Self.framedProject(rotation: 0), content: content))
        let turned = try Self.silhouetteBounds(
            try Renderer.render(project: Self.framedProject(rotation: 90), content: content))
        // Content 400×260 plus the 28 px title bar = a 400×288 window; rotated it is 288×400 (±1 px).
        #expect(abs(upright.width - 400) <= 1 && abs(upright.height - 288) <= 1, "\(upright)")
        #expect(abs(turned.width - 288) <= 1 && abs(turned.height - 400) <= 1, "\(turned)")
    }

    @Test("[S6-AC8] rotated mac window with border and shadow matches its snapshot")
    func rotatedFrameSnapshot() throws {
        let content = try SampleContent.image(width: 400, height: 260)
        var project = Self.framedProject(rotation: 20, shadow: Shadow(style: .spread, intensity: .high))
        project.border = Border(style: .smooth, radius: 24)
        project.frame.title = "Release notes"
        let image = try Renderer.render(project: project, content: content)
        try assertSnapshot(image, named: "s6-s5-rotation-20-mac-window")
    }
}
