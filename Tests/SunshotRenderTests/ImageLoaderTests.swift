import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

@Suite("Image loading")
struct ImageLoaderTests {
    @Test("[S1-AC2] PNG, JPEG, HEIC and TIFF decode at their pixel size", arguments: [UTType.png, .jpeg, .heic, .tiff])
    func readableFormats(type: UTType) throws {
        let data = try Fixtures.encode(Fixtures.solid(width: 40, height: 24), as: type)
        let image = try ImageLoader.load(data)
        #expect((image.width, image.height) == (40, 24))
    }

    @Test("[S1-AC2] WebP decodes")
    func webP() throws {
        let image = try ImageLoader.load(Fixtures.webP)
        #expect(image.width >= 1 && image.height >= 1)
    }

    @Test("[S1-AC2] every advertised type is an image type")
    func supportedTypes() {
        #expect(ImageLoader.supportedTypes.allSatisfy { $0.conforms(to: .image) })
        #expect(ImageLoader.supportedTypes.contains(.webP))
    }

    @Test("[S1-AC3] empty data is rejected as empty")
    func emptyData() {
        #expect(throws: ImageLoadError.empty) { try ImageLoader.load(Data()) }
    }

    @Test("[S1-AC3] truncated PNG, text renamed .png and PDF are rejected with a one-line reason")
    func corruptOrUnsupported() throws {
        let png = try Fixtures.encode(Fixtures.noise(width: 128, height: 128), as: .png)
        let bad = [png.prefix(png.count / 2), Data("hello, not an image".utf8), Fixtures.pdf()]
        for data in bad {
            #expect(throws: ImageLoadError.self) { try ImageLoader.load(Data(data)) }
            do {
                _ = try ImageLoader.load(Data(data))
            } catch let error as ImageLoadError {
                #expect(!error.reason.isEmpty && !error.reason.contains("\n"))
            }
        }
    }

    @Test("[S1-AC3] truncated JPEG is rejected; complete files with trailing padding are accepted")
    func truncationMarkers() throws {
        let jpeg = try Fixtures.encode(Fixtures.noise(width: 128, height: 128), as: .jpeg)
        #expect(throws: ImageLoadError.unreadable) { try ImageLoader.load(Data(jpeg.prefix(jpeg.count * 2 / 3))) }
        let png = try Fixtures.encode(Fixtures.solid(width: 8, height: 8), as: .png)
        #expect(try ImageLoader.load(png + Data(repeating: 0, count: 16)).width == 8)
    }

    @Test("[S1-AC9] EXIF orientation 6 is applied: content size is the displayed (rotated) size")
    func exifOrientation() throws {
        let source = try Fixtures.draw(width: 40, height: 20) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let data = try Fixtures.encode(source, as: .jpeg, properties: [kCGImagePropertyOrientation: 6])
        let image = try ImageLoader.load(data)
        #expect((image.width, image.height) == (20, 40))
    }

    @Test("[S1-AC9] Display P3 pixels are converted to sRGB (within ΔE ≤ 2, ±2 per channel)")
    func displayP3() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)
        // Fill with an in-gamut sRGB colour; Core Graphics stores it as P3 values with a P3 profile.
        let source = try Fixtures.draw(width: 8, height: 8, colorSpace: p3) { context in
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.4, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let stored = try Fixtures.rawPixel(source, x: 4, y: 4)
        #expect(stored != [204, 102, 51, 255], "fixture must really be P3-encoded")

        let image = try ImageLoader.load(Fixtures.encode(source, as: .png))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        let pixel = try PixelBuffer(image).pixel(x: 4, y: 4)
        for (actual, expected) in zip(pixel, [204, 102, 51, 255]) {
            #expect(abs(Int(actual) - expected) <= 2)
        }
    }

    @Test("[S0] ImageLoadError reasons are user-facing")
    func reasons() {
        #expect(ImageLoadError.empty.reason.contains("empty"))
        #expect(!ImageLoadError.unsupportedType("PDF").reason.isEmpty)
        #expect(!ImageLoadError.unreadable.reason.isEmpty)
    }
}
