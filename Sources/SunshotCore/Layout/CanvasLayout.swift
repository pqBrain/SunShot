/// Result of laying out content on the canvas, in canvas pixels (1 canvas px = 1 output px at 1× export).
public struct CanvasLayout: Hashable, Sendable {
    public let canvasSize: PixelSize
    public let contentRect: LayoutRect

    /// Lays out content of `contentSize` according to `project`.
    ///
    /// - `auto`: canvas = content + padding on every side.
    /// - `ratio`: the smallest canvas of that ratio that fits content + padding; content is never scaled.
    /// - `exact`: the given canvas; content is scaled to fit inside the padded area.
    public static func compute(contentSize: PixelSize, project: Project) -> CanvasLayout {
        let contentWidth = Double(contentSize.width)
        let contentHeight = Double(contentSize.height)
        let inset = project.padding
        let paddedWidth = contentWidth + inset * 2
        let paddedHeight = contentHeight + inset * 2

        switch project.canvas {
        case .auto:
            let canvas = PixelSize(width: Int(paddedWidth.rounded()), height: Int(paddedHeight.rounded()))
            return centered(contentWidth, contentHeight, in: canvas)

        case .ratio(let rawRatio):
            let ratio = rawRatio.isFinite && rawRatio > 0 ? rawRatio : 1
            var width = paddedWidth
            var height = paddedWidth / ratio
            if height < paddedHeight {
                height = paddedHeight
                width = paddedHeight * ratio
            }
            let canvas = PixelSize(width: Int(width.rounded()), height: Int(height.rounded()))
            return centered(contentWidth, contentHeight, in: canvas)

        case .exact(let canvas):
            let availableWidth = Double(canvas.width) - inset * 2
            let availableHeight = Double(canvas.height) - inset * 2
            guard availableWidth > 0, availableHeight > 0 else {
                return centered(0, 0, in: canvas)
            }
            let scale = min(availableWidth / contentWidth, availableHeight / contentHeight)
            return centered(contentWidth * scale, contentHeight * scale, in: canvas)
        }
    }

    private static func centered(_ width: Double, _ height: Double, in canvas: PixelSize) -> CanvasLayout {
        let rect = LayoutRect(
            x: (Double(canvas.width) - width) / 2,
            y: (Double(canvas.height) - height) / 2,
            width: width,
            height: height
        )
        return CanvasLayout(canvasSize: canvas, contentRect: rect)
    }
}
