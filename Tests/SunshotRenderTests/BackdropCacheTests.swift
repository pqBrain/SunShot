import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// The backdrop cache must be invisible: a render served from it is byte-identical to one drawn from scratch.
@Suite("Backdrop cache", .serialized)
struct BackdropCacheTests {
    static let canvas = CanvasSpec.exact(PixelSize(width: 1400, height: 1000))

    static func project(radius: Double, backdrop: Backdrop) -> Project {
        var project = Project.plain(canvas: canvas, backdrop: backdrop, padding: 120)
        project.border = Border(style: .round, radius: radius)
        project.backdropSettings.effects.adjustments.blur = 6
        return project
    }

    static func render(_ project: Project, content: CGImage, grid: TransparencyGrid? = nil) throws -> [UInt8] {
        try PixelBuffer(Renderer.render(project: project, content: content, grid: grid)).bytes
    }

    @Test("a content-only change reuses the cached backdrop with byte-identical output")
    func hitMatchesFreshRender() throws {
        let content = try SampleContent.image()
        let gradient = Backdrop.gradient(SunshotDefaults.gradient)
        // Prime the cache with a preview render, then change only the corners: the backdrop comes from the cache.
        _ = try Self.render(Self.project(radius: 10, backdrop: gradient), content: content, grid: .standard)
        #expect(BackdropCache.shared.contains(width: 1400, height: 1000))
        let cached = try Self.render(Self.project(radius: 60, backdrop: gradient), content: content, grid: .standard)
        BackdropCache.shared.removeAll()
        let fresh = try Self.render(Self.project(radius: 60, backdrop: gradient), content: content, grid: .standard)
        #expect(cached == fresh)
    }

    @Test("exports (no transparency grid) are never cached, and purgeCaches empties the cache")
    func exportsBypassAndPurge() throws {
        let content = try SampleContent.image()
        let gradient = Backdrop.gradient(SunshotDefaults.gradient)
        BackdropCache.shared.removeAll()
        _ = try Self.render(Self.project(radius: 10, backdrop: gradient), content: content)
        #expect(!BackdropCache.shared.contains(width: 1400, height: 1000))
        _ = try Self.render(Self.project(radius: 10, backdrop: gradient), content: content, grid: .standard)
        #expect(BackdropCache.shared.contains(width: 1400, height: 1000))
        Renderer.purgeCaches()
        #expect(!BackdropCache.shared.contains(width: 1400, height: 1000))
    }

    @Test("a backdrop or grid change misses the cache")
    func backdropChangeMisses() throws {
        let content = try SampleContent.image()
        let solid = Backdrop.solid(RGBAColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        let translucent = Backdrop.solid(RGBAColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 0.5))
        let grid = TransparencyGrid(
            light: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1), dark: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1))
        let first = try Self.render(Self.project(radius: 10, backdrop: solid), content: content)
        let second = try Self.render(Self.project(radius: 10, backdrop: translucent), content: content)
        let withGrid = try Self.render(Self.project(radius: 10, backdrop: translucent), content: content, grid: grid)
        #expect(first != second)
        #expect(second != withGrid)
    }

    @Test("small renders (thumbnails) bypass the cache")
    func smallRendersBypass() throws {
        BackdropCache.shared.removeAll()
        var project = Project.plain(canvas: .exact(PixelSize(width: 200, height: 120)), backdrop: .none, padding: 10)
        project.border = Border(style: .sharp)
        let image = try Renderer.render(
            project: project, content: SampleContent.image(width: 100, height: 60), grid: .standard)
        #expect(image.width == 200)
        #expect(!BackdropCache.shared.contains(width: 200, height: 120))
    }
}
