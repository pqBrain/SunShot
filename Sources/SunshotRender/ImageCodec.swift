public import CoreGraphics
public import Foundation
import ImageIO
public import SunshotCore

public enum ImageCodecError: Error, Equatable {
    case decodeFailed
    case encodeFailed
}

/// Encodes and decodes images through ImageIO.
public enum ImageCodec {
    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageCodecError.decodeFailed }
        return image
    }

    public static func pngData(_ image: CGImage) throws -> Data { try encode(image, as: .png) }

    /// Formats ImageIO can write on the running OS, in display order (WebP only if the OS can encode it).
    public static var writableFormats: [ExportFormat] {
        let identifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return ExportFormat.allCases.filter { identifiers.contains($0.typeIdentifier) }
    }

    public static func canWrite(_ format: ExportFormat) -> Bool { writableFormats.contains(format) }

    /// Encodes `image`. JPEG has no alpha, so it is flattened onto white first (never a black background);
    /// JPEG and HEIC use `SunshotDefaults.lossyQuality`.
    public static func encode(_ image: CGImage, as format: ExportFormat) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, format.typeIdentifier as CFString, 1, nil)
        else { throw ImageCodecError.encodeFailed }
        var properties: [CFString: Any] = [:]
        var source = image
        if format == .jpeg || format == .heic || format == .webp {
            properties[kCGImageDestinationLossyCompressionQuality] = SunshotDefaults.lossyQuality
        }
        if !format.supportsTransparency { source = try flattenedOnWhite(image) }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodeFailed }
        return output as Data
    }

    /// `image` composited over opaque white, without an alpha channel.
    static func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ImageCodecError.encodeFailed }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else { throw ImageCodecError.encodeFailed }
        return flattened
    }
}
