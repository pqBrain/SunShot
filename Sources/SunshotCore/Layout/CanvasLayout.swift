/// Result of laying out content on the canvas, in canvas pixels (1 canvas px = 1 output px at 1× export).
public struct CanvasLayout: Hashable, Sendable {
    public let canvasSize: PixelSize
    /// Where the content lands, after any `styleScale`.
    public let contentRect: LayoutRect
    /// Where the frame box (content + frame chrome, see `FrameGeometry`) lands. Equals `contentRect` for frame none.
    public let frameRect: LayoutRect
    /// How much the padded content (and with it corner radius and shadow) is scaled to fit an exact canvas.
    /// 1 for Auto and ratio canvases, which never scale the content.
    public let styleScale: Double

    public init(
        canvasSize: PixelSize, contentRect: LayoutRect, styleScale: Double = 1, frameRect: LayoutRect? = nil
    ) {
        self.canvasSize = canvasSize
        self.contentRect = contentRect
        self.styleScale = styleScale
        self.frameRect = frameRect ?? contentRect
    }

    /// Lays out content of `contentSize` according to `project`.
    ///
    /// - `auto`: canvas = content + padding on every side.
    /// - `ratio`: the smallest canvas of that ratio that fits content + padding; content is never scaled.
    /// - `exact` (and store presets): the given canvas; content + padding is scaled uniformly to fit, centred.
    /// - `custom`: like `exact`; a missing side follows the Auto canvas's ratio.
    ///
    /// Frame chrome (S5) is laid out as part of the content: the frame box (content + chrome) is what gets padded,
    /// so chrome grows an Auto canvas and never covers or scales the content.
    public static func compute(contentSize: PixelSize, project: Project) -> CanvasLayout {
        // S12: with a device mockup the laid-out content is the device screen cut from the content.
        let laid = FrameGeometry.layoutBox(for: project, contentSize: contentSize)
        let insets = laid.insets
        let box = boxLayout((laid.width + insets.horizontal, laid.height + insets.vertical), project: project)
        let style = box.styleScale
        let frame = box.contentRect
        let content = LayoutRect(
            x: frame.x + insets.left * style, y: frame.y + insets.top * style,
            width: frame.width - insets.horizontal * style, height: frame.height - insets.vertical * style)
        return CanvasLayout(canvasSize: box.canvasSize, contentRect: content, styleScale: style, frameRect: frame)
    }

    /// Lays out a box of `content` size (the frame box) as if it were the content.
    private static func boxLayout(_ content: (width: Double, height: Double), project: Project) -> CanvasLayout {
        let inset = project.padding
        let padded = (width: content.width + inset * 2, height: content.height + inset * 2)

        switch project.canvas {
        case .auto:
            return centered(content, in: PixelSize(width: rounded(padded.width), height: rounded(padded.height)))

        case .ratio(let ratio):
            return ratioLayout(ratio, content: content, padded: padded)

        case .preset(let preset):
            if let size = preset.exactSize { return fitted(content, padded: padded, in: size) }
            return ratioLayout(preset.ratio, content: content, padded: padded)

        case .exact(let canvas):
            return fitted(content, padded: padded, in: canvas)

        case .custom(let custom):
            switch (custom.width, custom.height) {
            case (nil, nil):
                return centered(content, in: PixelSize(width: rounded(padded.width), height: rounded(padded.height)))
            case (let width?, let height?):
                return fitted(content, padded: padded, in: PixelSize(width: width, height: height))
            case (let width?, nil):
                let height = rounded(Double(width) * padded.height / padded.width)
                return fitted(content, padded: padded, in: PixelSize(width: width, height: height))
            case (nil, let height?):
                let width = rounded(Double(height) * padded.width / padded.height)
                return fitted(content, padded: padded, in: PixelSize(width: width, height: height))
            }
        }
    }

    private static func rounded(_ value: Double) -> Int { Int(saturatingLength: value) }

    private static func ratioLayout(
        _ rawRatio: Double, content: (width: Double, height: Double), padded: (width: Double, height: Double)
    ) -> CanvasLayout {
        let ratio = rawRatio.isFinite && rawRatio > 0 ? min(max(rawRatio, 1e-3), 1e3) : 1
        var width = padded.width
        var height = padded.width / ratio
        if height < padded.height {
            height = padded.height
            width = padded.height * ratio
        }
        return centered(content, in: PixelSize(width: rounded(width), height: rounded(height)))
    }

    /// Scales content + padding uniformly so it fits `canvas`, centred.
    private static func fitted(
        _ content: (width: Double, height: Double), padded: (width: Double, height: Double), in canvas: PixelSize
    ) -> CanvasLayout {
        // Exact and custom sizes come straight from the document: cap them like computed lengths.
        let canvas = PixelSize(
            width: min(canvas.width, Int.maxLayoutLength), height: min(canvas.height, Int.maxLayoutLength))
        let scale = min(Double(canvas.width) / padded.width, Double(canvas.height) / padded.height)
        return centered((content.width * scale, content.height * scale), in: canvas, styleScale: scale)
    }

    private static func centered(
        _ content: (width: Double, height: Double), in canvas: PixelSize, styleScale: Double = 1
    ) -> CanvasLayout {
        let rect = LayoutRect(
            x: (Double(canvas.width) - content.width) / 2,
            y: (Double(canvas.height) - content.height) / 2,
            width: content.width,
            height: content.height
        )
        return CanvasLayout(canvasSize: canvas, contentRect: rect, styleScale: styleScale)
    }
}
