public import CoreGraphics
public import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    public static func pngData(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw ImageCodecError.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodeFailed }
        return output as Data
    }
}
