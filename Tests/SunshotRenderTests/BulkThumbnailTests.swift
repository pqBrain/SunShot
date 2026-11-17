import CoreGraphics
import Foundation
import ImageIO
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

/// A temporary folder for batch files, removed by `cleanUp()`.
struct BulkFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("sunshot-bulk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// Writes a solid PNG and returns its batch item.
    @discardableResult
    func png(_ name: String, width: Int = 160, height: Int = 100, red: CGFloat = 0.2) throws -> BulkItem {
        let target = file(name)
        try Fixtures.encode(Fixtures.solid(width: width, height: height, red: red), as: .png).write(to: target)
        return BulkItem(url: target)
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: url) }
}

@Suite("Bulk strip thumbnails")
struct BulkThumbnailTests {
    private func styled() -> EditorSession {
        var session = EditorSession()
        session.setCornerRadius(40)
        session.setShadowIntensity(.high)
        session.setBackdropKind(.gradient)
        return session
    }

    @Test("[S14-AC6] the thumbnail is the one renderer's output: same canvas aspect, matches the downscaled export")
    func sameRenderer() throws {
        let folder = try BulkFolder()
        defer { folder.cleanUp() }
        let item = try folder.png("shot.png", width: 1600, height: 1000)
        let project = styled().project
        let proxy = try BulkThumbnailer.proxy(for: item.url)
        let thumbnail = try BulkThumbnailer.render(proxy, project: project)

        let full = try Renderer.render(project: project, content: try Fixtures.solid(width: 1600, height: 1000))
        #expect(max(thumbnail.width, thumbnail.height) == BulkThumbnailer.thumbnailLongEdge)
        let expectedHeight = Double(BulkThumbnailer.thumbnailLongEdge) * Double(full.height) / Double(full.width)
        #expect(abs(Double(thumbnail.height) - expectedHeight) <= 1)

        let direct = try Renderer.render(
            project: project, content: proxy.image, scale: Double(thumbnail.width) / Double(full.width),
            layoutSize: proxy.pixelSize)
        #expect(try PixelBuffer(direct).bytes == PixelBuffer(thumbnail).bytes)

        let downscaled = try #require(
            BorderShadowRenderTests.resize(full, width: thumbnail.width, height: thumbnail.height))
        let ssim = BorderShadowRenderTests.ssim(try PixelBuffer(thumbnail), try PixelBuffer(downscaled))
        #expect(ssim >= 0.9, "SSIM \(ssim)")
    }

    @Test("[S14-AC7] proxies are downsampled from the file, keep the true size and apply EXIF orientation")
    func downsampled() throws {
        let folder = try BulkFolder()
        defer { folder.cleanUp() }
        let large = try folder.png("large.png", width: 3000, height: 2000)
        let proxy = try BulkThumbnailer.proxy(for: large.url)
        #expect(proxy.pixelSize == PixelSize(width: 3000, height: 2000))
        #expect(max(proxy.image.width, proxy.image.height) == BulkThumbnailer.proxyMaxSide)

        let small = try folder.png("small.png", width: 100, height: 50)
        let smallProxy = try BulkThumbnailer.proxy(for: small.url)
        #expect((smallProxy.image.width, smallProxy.image.height) == (100, 50), "never upscaled")

        let rotated = folder.file("rotated.jpg")
        try Fixtures.encode(
            Fixtures.solid(width: 300, height: 200), as: .jpeg, properties: [kCGImagePropertyOrientation: 6]
        ).write(to: rotated)
        let rotatedProxy = try BulkThumbnailer.proxy(for: rotated)
        #expect(rotatedProxy.pixelSize == PixelSize(width: 200, height: 300))
        #expect(rotatedProxy.image.height > rotatedProxy.image.width)
    }

    @Test("[S14-AC8] corrupt, truncated, empty, missing and non-raster files are refused with a reason")
    func unreadable() throws {
        let folder = try BulkFolder()
        defer { folder.cleanUp() }
        let corrupt = folder.file("corrupt.png")
        try Data("not an image at all".utf8).write(to: corrupt)
        let empty = folder.file("empty.png")
        try Data().write(to: empty)
        let truncated = folder.file("truncated.png")
        let png = try Fixtures.encode(Fixtures.noise(width: 64, height: 64), as: .png)
        try png.prefix(png.count / 2).write(to: truncated)
        let pdf = folder.file("doc.pdf")
        try Fixtures.pdf().write(to: pdf)

        #expect(throws: ImageLoadError.unreadable) { try BulkThumbnailer.proxy(for: corrupt) }
        #expect(throws: ImageLoadError.empty) { try BulkThumbnailer.proxy(for: empty) }
        #expect(throws: ImageLoadError.unreadable) { try BulkThumbnailer.proxy(for: truncated) }
        #expect(throws: (any Error).self) { try BulkThumbnailer.proxy(for: folder.file("missing.png")) }
        #expect {
            try BulkThumbnailer.proxy(for: pdf)
        } throws: { error in
            if case ImageLoadError.unsupportedType = error { return true }
            return false
        }
    }
}

@Suite("Bulk: the batch item on the canvas")
struct BulkCanvasContentTests {
    @Test("[S14-AC9] switching items records no undo step; undo and redo change only the style")
    func switchingIsNotAnEdit() throws {
        var session = EditorSession()
        let first = try Fixtures.solid(width: 40, height: 30)
        let second = try Fixtures.solid(width: 80, height: 50, red: 0.9)
        session.showBulkContent(first)
        #expect(session.history.undoCount == 0)
        session.setCornerRadius(10)
        session.beginGesture()
        session.setCornerRadius(12)
        session.showBulkContent(second)
        session.endGesture(EditorSession.cornerRadiusActionName)
        #expect(session.history.undoCount == 2)
        #expect(session.document.content?.pixelSize == PixelSize(width: 80, height: 50))

        session.undo()
        #expect(session.project.border.radius == 10)
        #expect(session.document.content?.pixelSize == PixelSize(width: 80, height: 50))
        session.undo()
        #expect(session.project.border.radius == SunshotDefaults.cornerRadius)
        #expect(session.document.content?.pixelSize == PixelSize(width: 80, height: 50))
        session.showBulkContent(first)
        session.redo()
        #expect(session.project.border.radius == 10)
        #expect(session.document.content?.pixelSize == PixelSize(width: 40, height: 30))
        session.showBulkContent(nil)
        #expect(!session.hasContent)
    }
}
