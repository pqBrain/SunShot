public import CoreGraphics
public import Foundation
import ImageIO
public import UniformTypeIdentifiers

public enum ImageLoadError: Error, Equatable, Sendable {
    case empty
    case unsupportedType(String)
    case unreadable

    /// One-line, user-facing reason.
    public var reason: String {
        switch self {
        case .empty: "The file is empty."
        case .unsupportedType(let type): "\(type) files aren't supported. Use PNG, JPEG, HEIC, TIFF or WebP."
        case .unreadable: "The file is damaged or isn't an image."
        }
    }
}

/// Decodes user images: applies EXIF orientation, converts to 8-bit sRGB RGBA, rejects partial/non-image data.
public enum ImageLoader {
    public static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .webP]

    public static func load(_ data: Data) throws -> CGImage {
        guard !data.isEmpty else { throw ImageLoadError.empty }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let typeIdentifier = CGImageSourceGetType(source) as String?,
            let type = UTType(typeIdentifier)
        else { throw ImageLoadError.unreadable }
        guard type.conforms(to: .image), !type.conforms(to: .pdf) else {
            throw ImageLoadError.unsupportedType(type.localizedDescription ?? typeIdentifier)
        }
        guard !isTruncated(data, type: type), CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatus(source) == .statusComplete,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw ImageLoadError.unreadable }

        // The thumbnail API is the supported way to apply EXIF orientation; max size = full size keeps all pixels.
        let decodeOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions) else {
            throw ImageLoadError.unreadable
        }
        return try normalized(decoded)
    }

    /// ImageIO reports partial PNG/JPEG files as complete and fills missing rows with grey, so check that the
    /// format's end marker is present (allowing a little trailing padding).
    static func isTruncated(_ data: Data, type: UTType) -> Bool {
        let tail = data.suffix(64)
        if type.conforms(to: .png) {
            return tail.firstRange(of: Data("IEND".utf8)) == nil
        }
        if type.conforms(to: .jpeg) {
            return tail.firstRange(of: Data([0xFF, 0xD9])) == nil
        }
        return false
    }

    /// Redraws into the renderer's canonical format (sRGB, 8 bpc, premultiplied RGBA).
    static func normalized(_ image: CGImage) throws -> CGImage {
        guard let context = Renderer.makeContext(width: image.width, height: image.height) else {
            throw RenderError.contextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw RenderError.imageCreationFailed }
        return result
    }
}
