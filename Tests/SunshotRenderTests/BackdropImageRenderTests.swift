import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Image backdrops, parity and thumbnails")
struct BackdropImageRenderTests {
    @Test(
        "[S3-AC14] wide and tall images cover wide and tall canvases, centred, with no empty pixels",
        arguments: [(4000, 1000), (1000, 4000)], [(1128, 728), (728, 1128)])
    func coverScaling(image: (Int, Int), canvas: (Int, Int)) throws {
        let source = try BackdropFixtures.quadrants(width: image.0, height: image.1)
        let asset = try BackdropFixtures.asset(source)
        let rendered = try Renderer.renderBackdrop(
            .image(.file(asset.reference)), size: PixelSize(width: canvas.0, height: canvas.1),
            media: [asset.reference.id: asset])
        let pixels = try PixelBuffer(rendered)
        let empty = stride(from: 3, to: pixels.bytes.count, by: 4).filter { pixels.bytes[$0] != 255 }.count
        #expect(empty == 0, "\(empty) uncovered pixels")
        let (w, h) = (canvas.0, canvas.1)
        #expect(BackdropFixtures.close(pixels.pixel(x: w / 2, y: h / 2), BackdropFixtures.centre))
        // The centre square is centred: equally far from the canvas centre on every side.
        let row = (0..<w).map { BackdropFixtures.close(pixels.pixel(x: $0, y: h / 2), BackdropFixtures.centre) }
        let column = (0..<h).map { BackdropFixtures.close(pixels.pixel(x: w / 2, y: $0), BackdropFixtures.centre) }
        let left = try #require(row.firstIndex(of: true))
        let right = try #require(row.lastIndex(of: true))
        let top = try #require(column.firstIndex(of: true))
        let bottom = try #require(column.lastIndex(of: true))
        #expect(abs((left + right) - (w - 1)) <= 2 && abs((top + bottom) - (h - 1)) <= 2)
        // Not mirrored: the top-left quadrant is still at the top left (where the crop leaves it visible).
        let probes = [
            (
                pixels.pixel(x: w / 2 - 4 - (right - left) / 2, y: h / 2 - 4 - (bottom - top) / 2),
                BackdropFixtures.topLeft
            ),
            (
                pixels.pixel(x: w / 2 + 4 + (right - left) / 2, y: h / 2 + 4 + (bottom - top) / 2),
                BackdropFixtures.bottomRight
            ),
        ]
        #expect(probes.allSatisfy { BackdropFixtures.close($0.0, $0.1) })
        try assertSnapshot(rendered, named: "s3-image-\(image.0)x\(image.1)-on-\(w)x\(h)")
    }

    @Test("[S3-AC13] a missing image falls back to the default colour; the cover rect is centred")
    func missingMedia() throws {
        let reference = MediaReference(id: "gone", fileName: nil, pixelSize: PixelSize(width: 10, height: 10))
        let pixels = try PixelBuffer(
            Renderer.renderBackdrop(.image(.file(reference)), size: PixelSize(width: 8, height: 8)))
        #expect(pixels.pixel(x: 4, y: 4) == [237, 237, 242, 255])
        let rect = BackdropRenderer.coverRect(
            imageWidth: 400, imageHeight: 100, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rect == CGRect(x: -150, y: 0, width: 400, height: 100))
    }

    private static func session(_ backdrop: Backdrop, media: [String: MediaAsset], content: CGImage) -> EditorSession {
        var session = EditorSession(document: EditorDocument(project: Project(backdrop: backdrop), media: media))
        session.setContent(content)
        return session
    }

    /// One session per backdrop type. `detailed` uses the sample screenshot; otherwise solid content isolates the
    /// backdrop (resampling detailed content is an S1 concern).
    private static func allBackdrops(detailed: Bool = true) throws -> [(String, EditorSession)] {
        let asset = try BackdropFixtures.asset(BackdropFixtures.quadrants(width: 900, height: 500))
        let content =
            detailed ? try SampleContent.image(width: 300, height: 200) : try Fixtures.solid(width: 300, height: 200)
        let backdrops: [(String, Backdrop)] = [
            ("none", .none),
            ("solid", .solid(RGBAColor(rgb: 0x2EC4B6))),
            ("gradient", .gradient(SunshotDefaults.gradient)),
            ("radial", .gradient(BackdropFixtures.gradient((0, 0xFFFFFF), (1, 0x1E1F25), kind: .radial))),
            ("wallpaper", .image(.wallpaper(SunshotDefaults.wallpaper))),
            ("file", .image(.file(asset.reference))),
        ]
        return backdrops.map { ($0.0, session($0.1, media: [asset.reference.id: asset], content: content)) }
    }

    @Test("[S3-AC18] every backdrop type: preview and export are byte-identical at 1× and 2×")
    func parity() throws {
        var mismatches: [String] = []
        for (name, session) in try Self.allBackdrops() {
            for scale in [1.0, 2.0] {
                let preview = try #require(try Renderer.render(document: session.document, scale: scale))
                let exported = try ImageCodec.decode(session.exportPNG(scale: scale))
                if try PixelBuffer(preview).bytes != PixelBuffer(exported).bytes {
                    mismatches.append("\(name)@\(scale)")
                }
            }
        }
        #expect(mismatches.isEmpty, "preview ≠ export for \(mismatches)")
    }

    @Test("[S3-AC18] gradients and images at 2× are proportionally identical to 1× (SSIM ≥ 0.98)")
    func scaleIndependence() throws {
        var scores: [String: Double] = [:]
        for (name, session) in try Self.allBackdrops(detailed: false) where !["none", "solid"].contains(name) {
            let one = try #require(try session.render(scale: 1))
            let two = try #require(try session.render(scale: 2))
            let resized = try #require(BorderShadowRenderTests.resize(two, width: one.width, height: one.height))
            scores[name] = BorderShadowRenderTests.ssim(try PixelBuffer(one), try PixelBuffer(resized))
        }
        #expect(scores.count == 4 && scores.values.allSatisfy { $0 >= 0.98 }, "\(scores)")
    }

    @Test("[S3-AC7] [S3-AC15] thumbnails come from the same renderer as the canvas")
    func thumbnailsUseTheCanvasRenderer() throws {
        let size = PixelSize(width: 112, height: 70)
        let transparent = try Fixtures.draw(width: 1, height: 1) { _ in }
        let backdrops: [Backdrop] = [
            .gradient(SunshotDefaults.gradient), .image(.wallpaper(SunshotDefaults.wallpaper)),
            .gradient(BackdropFixtures.gradient((0, 0xFF0000), (1, 0x0000FF), kind: .radial)),
        ]
        let identical = try backdrops.allSatisfy { backdrop in
            let thumbnail = try Renderer.renderBackdrop(backdrop, size: size)
            let canvas = try Renderer.render(
                project: .plain(canvas: .exact(size), backdrop: backdrop), content: transparent)
            return try PixelBuffer(thumbnail).bytes == PixelBuffer(canvas).bytes
        }
        #expect(identical)
    }
}
