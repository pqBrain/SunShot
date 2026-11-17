public import CoreGraphics
public import Foundation
import ImageIO
public import SunshotCore
import UniformTypeIdentifiers

/// A small stand-in for a batch item: downsampled pixels plus the item's true (oriented) pixel size.
public struct BulkProxy: Sendable {
    public let image: CGImage
    public let pixelSize: PixelSize

    public init(image: CGImage, pixelSize: PixelSize) {
        self.image = image
        self.pixelSize = pixelSize
    }
}

/// Strip thumbnails. Files are decoded through ImageIO's downsampling straight from disk (never at full size),
/// and drawn by `Renderer.render` with the proxy laid out at the item's true size.
public enum BulkThumbnailer {
    /// Longest proxy edge: enough for a 200 px thumbnail, small enough that 500 proxies stay ~130 MB at worst.
    public static let proxyMaxSide = 256
    /// Long edge of a strip thumbnail in pixels (100 pt on a 2× display).
    public static let thumbnailLongEdge = 200

    /// Reads `url` into a proxy. Throws `ImageLoadError` for empty, unsupported, truncated or unreadable files.
    public static func proxy(for url: URL, maxSide: Int = proxyMaxSide) throws -> BulkProxy {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw (try? fileIsEmpty(url)) == true ? ImageLoadError.empty : ImageLoadError.unreadable
        }
        guard let typeIdentifier = CGImageSourceGetType(source) as String?, let type = UTType(typeIdentifier) else {
            throw (try? fileIsEmpty(url)) == true ? ImageLoadError.empty : ImageLoadError.unreadable
        }
        guard type.conforms(to: .image), !type.conforms(to: .pdf) else {
            throw ImageLoadError.unsupportedType(type.localizedDescription ?? typeIdentifier)
        }
        guard CGImageSourceGetCount(source) > 0, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            let size = orientedSize(source), !ImageLoader.isTruncated(try tail(of: url), type: type)
        else { throw ImageLoadError.unreadable }

        let decodeOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxSide, max(size.width, size.height))),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions) else {
            throw ImageLoadError.unreadable
        }
        return BulkProxy(image: try ImageLoader.normalized(decoded), pixelSize: size)
    }

    /// The strip thumbnail of `proxy` in `project`'s style: the one renderer, scaled so the canvas's long edge
    /// is `longEdge` pixels.
    public static func render(
        _ proxy: BulkProxy, project: Project, media: [String: MediaAsset] = [:],
        longEdge: Int = thumbnailLongEdge
    ) throws -> CGImage {
        let canvas = CanvasLayout.compute(contentSize: proxy.pixelSize, project: project).canvasSize
        let scale = Double(longEdge) / Double(max(canvas.width, canvas.height, 1))
        return try Renderer.render(
            project: project, content: proxy.image, media: media, scale: scale, layoutSize: proxy.pixelSize)
    }

    /// Pixel size after EXIF orientation (orientations 5–8 swap width and height).
    static func orientedSize(_ source: CGImageSource) -> PixelSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation)
            ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }

    /// The last 64 bytes of the file, for the end-marker check shared with `ImageLoader`.
    static func tail(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > 64 ? end - 64 : 0)
        return try handle.readToEnd() ?? Data()
    }

    private static func fileIsEmpty(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize == 0
    }
}
