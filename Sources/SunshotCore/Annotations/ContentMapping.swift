/// Maps between a displayed preview of the canvas (view points, origin top-left) and content pixels, which is
/// where annotations live. Accounts for padding/centering (`contentRect`), exact-size scaling (`styleScale`) and the
/// size the preview is displayed at.
public struct ContentMapping: Hashable, Sendable {
    public let layout: CanvasLayout
    public let contentSize: PixelSize
    /// Displayed size of the whole canvas, in view points.
    public let viewWidth: Double
    public let viewHeight: Double
    /// S10: where the drawn (cropped) content starts in the original image. Annotations are stored in uncropped
    /// content pixels, so content points include it.
    public let origin: AnnotationPoint

    public init(
        contentSize: PixelSize, project: Project, viewWidth: Double, viewHeight: Double,
        origin: AnnotationPoint = AnnotationPoint(x: 0, y: 0)
    ) {
        self.init(
            layout: CanvasLayout.compute(contentSize: contentSize, project: project), contentSize: contentSize,
            viewWidth: viewWidth, viewHeight: viewHeight, origin: origin)
    }

    public init(
        layout: CanvasLayout, contentSize: PixelSize, viewWidth: Double, viewHeight: Double,
        origin: AnnotationPoint = AnnotationPoint(x: 0, y: 0)
    ) {
        self.layout = layout
        self.contentSize = contentSize
        self.origin = origin
        self.viewWidth = viewWidth.isFinite && viewWidth > 0 ? viewWidth : Double(layout.canvasSize.width)
        self.viewHeight = viewHeight.isFinite && viewHeight > 0 ? viewHeight : Double(layout.canvasSize.height)
    }

    /// View points per canvas pixel, horizontally and vertically.
    private var viewPerCanvasX: Double { viewWidth / Double(layout.canvasSize.width) }
    private var viewPerCanvasY: Double { viewHeight / Double(layout.canvasSize.height) }
    private var styleScale: Double { layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1 }

    /// View points per content pixel (uniform: the preview keeps the canvas aspect ratio).
    public var viewPerContent: Double { viewPerCanvasX * styleScale }

    public func contentPoint(fromView x: Double, _ y: Double) -> AnnotationPoint {
        let canvasX = x / viewPerCanvasX
        let canvasY = y / viewPerCanvasY
        return AnnotationPoint(
            x: (canvasX - layout.contentRect.x) / styleScale + origin.x,
            y: (canvasY - layout.contentRect.y) / styleScale + origin.y)
    }

    public func viewPoint(fromContent point: AnnotationPoint) -> (x: Double, y: Double) {
        let canvasX = layout.contentRect.x + (point.x - origin.x) * styleScale
        let canvasY = layout.contentRect.y + (point.y - origin.y) * styleScale
        return (canvasX * viewPerCanvasX, canvasY * viewPerCanvasY)
    }

    /// A length in view points (e.g. a hit tolerance) in content pixels.
    public func contentLength(fromView length: Double) -> Double { length / viewPerContent }

    public func viewLength(fromContent length: Double) -> Double { length * viewPerContent }

    /// Whether a content point lies on the content image.
    public func isInsideContent(_ point: AnnotationPoint) -> Bool {
        let x = point.x - origin.x
        let y = point.y - origin.y
        return x >= 0 && y >= 0 && x <= Double(contentSize.width) && y <= Double(contentSize.height)
    }

    /// Long edge of the content in pixels (sizes S/M/L scale with it).
    public var contentLongEdge: Double { Double(max(contentSize.width, contentSize.height)) }
}
