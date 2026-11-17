import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Pixel checks use a top-left origin.
@Suite("Backdrop rendering")
struct BackdropRenderTests {
    private func backdrop(_ backdrop: Backdrop, _ width: Int, _ height: Int) throws -> PixelBuffer {
        try PixelBuffer(Renderer.renderBackdrop(backdrop, size: PixelSize(width: width, height: height)))
    }

    private func luma(_ pixel: [UInt8]) -> Int { Int(pixel[0]) }

    @Test("[S3-AC2] none: the export is transparent outside the content, keeps alpha and the content's own alpha")
    func noneIsTransparent() throws {
        // Opaque left half, 50 % right half.
        let content = try Fixtures.draw(width: 200, height: 120) { context in
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 120))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 0.5))
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 120))
        }
        var session = EditorSession(document: EditorDocument(project: .plain(backdrop: .none)))
        session.setContent(content)
        let png = try session.exportPNG()
        let exported = try ImageCodec.decode(png)
        #expect(![.none, .noneSkipLast, .noneSkipFirst].contains(exported.alphaInfo), "PNG keeps an alpha channel")
        let pixels = try PixelBuffer(exported)
        let pad = 64
        var outside = 0
        var opaqueOutside = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where !(pad..<pad + 200).contains(x) || !(pad..<pad + 120).contains(y) {
                outside += 1
                if pixels.pixel(x: x, y: y)[3] != 0 { opaqueOutside += 1 }
            }
        }
        #expect(outside > 0 && opaqueOutside == 0, "\(opaqueOutside) of \(outside) backdrop pixels are not alpha 0")
        #expect(pixels.pixel(x: pad + 50, y: pad + 60)[3] == 255)
        #expect(abs(Int(pixels.pixel(x: pad + 150, y: pad + 60)[3]) - 128) <= 1)
        try assertSnapshot(exported, named: "s3-none-transparent")
    }

    @Test("[S3-AC3] the checkerboard is drawn only when the preview asks; opaque backdrops ignore the flag")
    func previewGridOnly() throws {
        var session = EditorSession(document: EditorDocument(project: .plain(backdrop: .none)))
        session.setContent(try Fixtures.solid(width: 100, height: 60))
        let grid = TransparencyGrid(light: RGBAColor(rgb: 0xFFFFFF), dark: RGBAColor(rgb: 0xDCDCE1))
        let preview = try PixelBuffer(
            #require(try Renderer.render(document: session.document, showsTransparencyGrid: true, grid: grid)))
        let export = try PixelBuffer(ImageCodec.decode(session.exportPNG()))
        let side = Int(TransparencyGrid.defaultSquareSize)
        #expect(side == 16, "8 pt squares on a 2× display")
        let samples = [
            preview.pixel(x: 2, y: 2), preview.pixel(x: side + 2, y: 2), preview.pixel(x: 2, y: side + 2),
            preview.pixel(x: side + 2, y: side + 2),
        ]
        #expect(
            samples == [[220, 220, 225, 255], [255, 255, 255, 255], [255, 255, 255, 255], [220, 220, 225, 255]],
            "\(samples)")
        // Same pipeline: wherever the export is opaque (the content), preview and export agree exactly.
        var mismatched = 0
        var gridInExport = 0
        for offset in stride(from: 0, to: export.bytes.count, by: 4) {
            let alpha = export.bytes[offset + 3]
            if alpha == 255, export.bytes[offset..<offset + 4] != preview.bytes[offset..<offset + 4] { mismatched += 1 }
            if alpha != 0 && alpha != 255 { gridInExport += 1 }
        }
        #expect(mismatched == 0 && gridInExport == 0)
        // The dark grid variant differs; an opaque backdrop never shows the grid at all.
        let dark = TransparencyGrid(light: RGBAColor(rgb: 0x3A3A3F), dark: RGBAColor(rgb: 0x2A2A2E))
        let darkPreview = try PixelBuffer(
            #require(try Renderer.render(document: session.document, showsTransparencyGrid: true, grid: dark)))
        #expect(darkPreview.pixel(x: 2, y: 2) == [42, 42, 46, 255], "\(darkPreview.pixel(x: 2, y: 2))")
        session.setBackdropColor(RGBAColor(rgb: 0x336699))
        let opaqueWithFlag = try #require(try Renderer.render(document: session.document, showsTransparencyGrid: true))
        let opaqueWithout = try #require(try Renderer.render(document: session.document))
        #expect(try PixelBuffer(opaqueWithFlag).bytes == PixelBuffer(opaqueWithout).bytes)
    }

    @Test("[S3-AC6] #FF0000 at 50 % exports as (255, 0, 0, 128 ± 1); the preview shows the grid through it")
    func translucentSolid() throws {
        let red = RGBAColor(rgb: 0xFF0000, alpha: 0.5)
        var session = EditorSession(document: EditorDocument(project: .plain(backdrop: .solid(red))))
        session.setContent(try Fixtures.solid(width: 100, height: 60))
        let exported = try ImageCodec.decode(session.exportPNG())
        let pixels = try PixelBuffer(exported)
        let corners = [(0, 0), (pixels.width - 1, 0), (0, pixels.height - 1), (pixels.width - 1, pixels.height - 1)]
        let values = corners.map { BackdropFixtures.unpremultiplied(pixels.pixel(x: $0.0, y: $0.1)) }
        #expect(values.allSatisfy { $0[0] == 255 && $0[1] == 0 && $0[2] == 0 && abs($0[3] - 128) <= 1 }, "\(values)")
        let preview = try PixelBuffer(
            #require(try Renderer.render(document: session.document, showsTransparencyGrid: true)))
        let light = preview.pixel(x: 2, y: 2)
        let dark = preview.pixel(x: 18, y: 2)
        #expect(light[3] == 255 && dark[3] == 255 && light != dark && light[0] > light[1])
        try assertSnapshot(exported, named: "s3-solid-red-50")
    }

    @Test(
        "[S3-AC8] linear angles: 0° bottom→top, 90° left→right, 180° top→bottom, 270° right→left",
        arguments: [0.0, 90, 180, 270])
    func linearAngles(angle: Double) throws {
        let pixels = try backdrop(
            .gradient(BackdropFixtures.gradient((0, 0x000000), (1, 0xFFFFFF), angle: angle)), 1000, 1000)
        let (start, end): ((Int, Int), (Int, Int)) =
            switch angle {
            case 0: ((500, 999), (500, 0))
            case 90: ((0, 500), (999, 500))
            case 180: ((500, 0), (500, 999))
            default: ((999, 500), (0, 500))
            }
        let first = pixels.pixel(x: start.0, y: start.1)
        let last = pixels.pixel(x: end.0, y: end.1)
        #expect(BackdropFixtures.close(first, [0, 0, 0, 255]) && BackdropFixtures.close(last, [255, 255, 255, 255]))
    }

    @Test("[S3-AC8] 45° on 1600×900 covers the canvas from the bottom-left to the top-right corner")
    func diagonal() throws {
        let spec = BackdropFixtures.gradient((0, 0x000000), (1, 0xFFFFFF), angle: 45)
        let image = try Renderer.renderBackdrop(.gradient(spec), size: PixelSize(width: 1600, height: 900))
        let pixels = try PixelBuffer(image)
        #expect(BackdropFixtures.close(pixels.pixel(x: 0, y: 899), [0, 0, 0, 255]))
        #expect(BackdropFixtures.close(pixels.pixel(x: 1599, y: 0), [255, 255, 255, 255]))
        #expect(abs(luma(pixels.pixel(x: 800, y: 450)) - 128) <= 2, "the centre is mid-way")
        #expect(
            abs(luma(pixels.pixel(x: 0, y: 0)) + luma(pixels.pixel(x: 1599, y: 899)) - 255) <= 3, "mirrored corners")
        // Dither makes full-size references large; the snapshot is a 1/4 downscale of the 1600×900 render.
        let small = try #require(BorderShadowRenderTests.resize(image, width: 400, height: 225))
        try assertSnapshot(small, named: "s3-gradient-linear-45-1600x900")
    }

    @Test("[S3-AC9] radial on 1000×600: white centre, black farthest corner, centred")
    func radial() throws {
        let spec = BackdropFixtures.gradient((0, 0xFFFFFF), (1, 0x000000), kind: .radial)
        let image = try Renderer.renderBackdrop(.gradient(spec), size: PixelSize(width: 1000, height: 600))
        let pixels = try PixelBuffer(image)
        #expect(BackdropFixtures.close(pixels.pixel(x: 500, y: 300), [255, 255, 255, 255]))
        #expect(
            [(0, 0), (999, 0), (0, 599), (999, 599)].allSatisfy {
                BackdropFixtures.close(pixels.pixel(x: $0.0, y: $0.1), [0, 0, 0, 255])
            })
        let symmetric = [(100, 300, 899, 300), (500, 50, 500, 549), (200, 100, 799, 499)].allSatisfy {
            abs(luma(pixels.pixel(x: $0.0, y: $0.1)) - luma(pixels.pixel(x: $0.2, y: $0.3))) <= 1
        }
        #expect(symmetric)
        let small = try #require(BorderShadowRenderTests.resize(image, width: 250, height: 150))
        try assertSnapshot(small, named: "s3-gradient-radial-1000x600")
    }

    @Test("[S3-AC11] equal stop positions render a hard edge; same-colour stops render an exact flat fill")
    func hardEdgeAndFlat() throws {
        let edge = BackdropFixtures.gradient((0, 0xFF0000), (0.5, 0xFF0000), (0.5, 0x0000FF), (1, 0x0000FF))
        let pixels = try backdrop(.gradient(edge), 1000, 20)
        var wrong = 0
        for y in 0..<20 {
            for x in 0..<1000 where pixels.pixel(x: x, y: y) != (x < 500 ? [255, 0, 0, 255] : [0, 0, 255, 255]) {
                wrong += 1
            }
        }
        #expect(wrong == 0, "\(wrong) pixels off the hard edge")
        for hex: UInt32 in [0x808080, 0x1A2B3C] {
            let flat = try backdrop(
                .gradient(BackdropFixtures.gradient((0.3, hex), (0.3, hex), kind: .radial)), 300, 200)
            let expected = [UInt8(hex >> 16 & 0xFF), UInt8(hex >> 8 & 0xFF), UInt8(hex & 0xFF), 255]
            let distinct = Set(stride(from: 0, to: flat.bytes.count, by: 4).map { Array(flat.bytes[$0..<$0 + 4]) })
            #expect(distinct == [expected], "flat fill has \(distinct.count) values")
        }
    }

    @Test("[S3-AC12] #202020 → #282828 over 3840 px is dithered: no constant band wider than 8 px")
    func dithering() throws {
        let spec = BackdropFixtures.gradient((0, 0x202020), (1, 0x282828))
        var session = EditorSession(
            document: EditorDocument(
                project: .plain(canvas: .exact(PixelSize(width: 3840, height: 2160)), backdrop: .gradient(spec))))
        session.setContent(try Fixtures.draw(width: 1, height: 1) { _ in })
        let pixels = try PixelBuffer(ImageCodec.decode(session.exportPNG()))
        // A "band" is a run of columns whose every pixel has the same value.
        var longestBand = 0
        var run = 0
        var previous: UInt8?
        var offLevel = 0
        var levels = Set<UInt8>()
        for x in 0..<pixels.width {
            let fraction: Double = (Double(x) + 0.5) / Double(pixels.width)
            let ideal: Double = 32 + 8 * fraction
            let column: [UInt8] = (0..<pixels.height).map { pixels.bytes[($0 * pixels.width + x) * 4] }
            offLevel += column.filter { (Double($0) - ideal).magnitude >= 1 }.count
            levels.formUnion(column)
            let constant: UInt8? = column.allSatisfy { $0 == column[0] } ? column[0] : nil
            if let constant, constant == previous {
                run += 1
            } else {
                run = constant == nil ? 0 : 1
            }
            previous = constant
            longestBand = max(longestBand, run)
        }
        #expect(longestBand <= 8 && offLevel == 0 && levels.count >= 8, "band \(longestBand), off \(offLevel)")
    }
}
