/// A non-destructive crop (S10): the part of the content image that is shown, in whole content pixels with the
/// image's top-left at the origin. The original image bytes are never changed; the crop is applied when rendering.
public struct CropRect: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The whole image.
    public init(full size: PixelSize) {
        self.init(x: 0, y: 0, width: size.width, height: size.height)
    }

    public var size: PixelSize { PixelSize(width: width, height: height) }

    /// The crop limited to an image of `size`; nil when nothing of it is left (documents edited by hand, or a crop
    /// from a different image).
    public func clamped(to size: PixelSize) -> CropRect? {
        let minX = min(max(x, 0), size.width)
        let minY = min(max(y, 0), size.height)
        let maxX = min(max(x + max(width, 0), 0), size.width)
        let maxY = min(max(y + max(height, 0), 0), size.height)
        guard maxX - minX >= 1, maxY - minY >= 1 else { return nil }
        return CropRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether the crop covers the whole of an image of `size` (i.e. crops nothing).
    public func isFull(of size: PixelSize) -> Bool { self == CropRect(full: size) }

    public var layoutRect: LayoutRect {
        LayoutRect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))
    }

    /// Rounds a rect in content pixels to whole pixels inside an image of `size` (at least 1×1).
    public static func rounded(_ rect: LayoutRect, in size: PixelSize) -> CropRect {
        let minX = Int((rect.x.isFinite ? rect.x : 0).rounded())
        let minY = Int((rect.y.isFinite ? rect.y : 0).rounded())
        let maxX = Int(((rect.x + rect.width).isFinite ? rect.x + rect.width : 0).rounded())
        let maxY = Int(((rect.y + rect.height).isFinite ? rect.y + rect.height : 0).rounded())
        let candidate = CropRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return candidate.clamped(to: size) ?? CropRect(full: size)
    }
}

extension AnnotationLayer {
    /// Every annotation moved by `offset`. Annotations live in uncropped content pixels, so the renderer shifts
    /// them by minus the crop origin to draw them over the cropped image.
    public func shifted(by offset: AnnotationPoint) -> AnnotationLayer {
        guard offset.x != 0 || offset.y != 0 else { return self }
        var layer = self
        layer.translate(Set(items.map(\.id)), by: offset)
        return layer
    }
}
