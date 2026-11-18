import CoreGraphics
import Foundation
import Testing

@testable import SunshotRender

@Suite("App icon")
struct AppIconArtworkTests {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("[S17-AC5] the icon is drawn at every iconset size: opaque sun, clear corners")
    func everySize() throws {
        let names = AppIconArtwork.iconsetEntries.map(\.name)
        #expect(names.count == 10)
        #expect(names.contains("icon_16x16.png") && names.contains("icon_512x512@2x.png"))
        for entry in AppIconArtwork.iconsetEntries {
            let image = try #require(AppIconArtwork.image(pixels: entry.pixels))
            #expect(image.width == entry.pixels && image.height == entry.pixels)
            let pixels = try rgba(image)
            let corner = pixels[0]
            let centre = pixels[(entry.pixels / 2) * entry.pixels + entry.pixels / 2]
            #expect(corner.alpha < 12, "corner outside the squircle (shadow only) at \(entry.pixels) px")
            #expect(centre.alpha == 255 && centre.red > 230 && centre.green > 220, "sun at \(entry.pixels) px")
        }
        let png = try #require(AppIconArtwork.pngData(pixels: 64))
        #expect(try ImageCodec.decode(png).width == 64)
        #expect(AppIconArtwork.image(pixels: 0) == nil)
    }

    @Test("[S17-AC5] the icon's look is pinned")
    func snapshot() throws {
        try assertSnapshot(try #require(AppIconArtwork.image(pixels: 256)), named: "app-icon-256")
    }

    @Test("[S17-AC5] the bundle names the icon and builds it from Sunshot's own drawing code")
    func bundleWiring() throws {
        let plist = try String(contentsOf: Self.repo.appendingPathComponent("Support/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<key>CFBundleIconFile</key><string>AppIcon</string>"))
        let bundle = try String(
            contentsOf: Self.repo.appendingPathComponent("scripts/bundle-app.sh"), encoding: .utf8)
        #expect(bundle.contains("scripts/make-app-icon.sh \"$APP/Contents/Resources/AppIcon.icns\""))
        let maker = try String(
            contentsOf: Self.repo.appendingPathComponent("scripts/make-app-icon.sh"), encoding: .utf8)
        #expect(maker.contains("Sources/SunshotRender/AppIconArtwork.swift") && maker.contains("iconutil -c icns"))
    }

    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    private func rgba(_ image: CGImage) throws -> [Pixel] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return stride(from: 0, to: bytes.count, by: 4).map {
            Pixel(red: bytes[$0], green: bytes[$0 + 1], blue: bytes[$0 + 2], alpha: bytes[$0 + 3])
        }
    }
}
