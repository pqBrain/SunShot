/// How the crop dialog shows the image (S10): fitted into the dialog, except tall images (long website captures),
/// which fill the width and scroll vertically so they stay large enough to crop precisely.
public struct CropDisplay: Hashable, Sendable {
    /// View points per content pixel.
    public let scale: Double
    /// The image is taller than the dialog and scrolls.
    public let scrolls: Bool

    /// A fitted image narrower than this fraction of the available width counts as tall.
    public static let tallWidthFraction = 0.35

    public init(imageSize: PixelSize, maxWidth: Double, maxHeight: Double) {
        let width = Double(imageSize.width)
        let height = Double(imageSize.height)
        let maxWidth = maxWidth.isFinite && maxWidth > 0 ? maxWidth : width
        let maxHeight = maxHeight.isFinite && maxHeight > 0 ? maxHeight : height
        // Never enlarge past 1 point per pixel.
        let fitWidth = min(maxWidth / width, 1)
        let fit = min(fitWidth, maxHeight / height)
        if width * fit < maxWidth * Self.tallWidthFraction, height * fitWidth > maxHeight {
            scale = fitWidth
            scrolls = true
        } else {
            scale = fit
            scrolls = false
        }
    }

    /// A view point (top-left origin of the displayed image) in content pixels.
    public func contentPoint(x: Double, y: Double) -> AnnotationPoint {
        AnnotationPoint(x: x / scale, y: y / scale)
    }

    /// A content rect in view points.
    public func viewRect(_ rect: LayoutRect) -> LayoutRect {
        LayoutRect(x: rect.x * scale, y: rect.y * scale, width: rect.width * scale, height: rect.height * scale)
    }
}
