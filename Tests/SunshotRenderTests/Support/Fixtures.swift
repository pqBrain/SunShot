import CoreGraphics
import Foundation
import ImageIO
import SunshotRender
import UniformTypeIdentifiers

/// Test images generated in code (no binary fixtures in the repo).
enum Fixtures {
    /// 1×1 lossless WebP (ImageIO can read WebP but not write it).
    static let webP = Data(base64Encoded: "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==") ?? Data()

    /// Solid opaque image in sRGB.
    static func solid(
        width: Int, height: Int, red: CGFloat = 0.2, green: CGFloat = 0.5, blue: CGFloat = 0.8
    ) throws
        -> CGImage
    {
        try draw(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Pseudo-random pixels (deterministic) so the encoded file is large and can be truncated mid-image.
    static func noise(width: Int, height: Int) throws -> CGImage {
        try draw(width: width, height: height) { context in
            var state: UInt32 = 12_345
            for y in 0..<height {
                for x in 0..<width {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    let value = CGFloat(state >> 24) / 255
                    context.setFillColor(CGColor(srgbRed: value, green: 1 - value, blue: value / 2, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    static func draw(
        width: Int, height: Int, colorSpace: CGColorSpace? = CGColorSpace(name: CGColorSpace.sRGB),
        _ body: (CGContext) -> Void
    ) throws -> CGImage {
        guard let colorSpace,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FixtureError.context }
        body(context)
        guard let image = context.makeImage() else { throw FixtureError.context }
        return image
    }

    /// Encodes `image` as `type` (PNG, JPEG, HEIC, TIFF) with optional ImageIO properties (e.g. orientation).
    static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw FixtureError.encode(type.identifier)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.encode(type.identifier) }
        return data as Data
    }

    /// RGBA bytes exactly as stored (no colour conversion). Expects 8-bit RGBA images from `draw`.
    static func rawPixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        guard let data = image.dataProvider?.data as Data? else { throw FixtureError.context }
        let offset = y * image.bytesPerRow + x * 4
        return Array(data[offset..<offset + 4])
    }

    /// A one-page PDF (a valid document that is not a raster image).
    static func pdf() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        if let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) {
            context.beginPDFPage(nil)
            context.fill(box)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }
}

enum FixtureError: Error {
    case context
    case encode(String)
}
