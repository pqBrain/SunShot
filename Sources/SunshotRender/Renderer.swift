public import CoreGraphics
public import SunshotCore

public enum RenderError: Error, Equatable {
    case contextCreationFailed
    case imageCreationFailed
}

/// The single render path shared by on-screen preview and export (guarantees preview/export parity).
public enum Renderer {
    /// Renders `project` with `content` at `scale` (1 = canvas points map to pixels).
    public static func render(project: Project, content: CGImage, scale: Double = 1) throws -> CGImage {
        let contentSize = PixelSize(width: content.width, height: content.height)
        let layout = CanvasLayout.compute(contentSize: contentSize, project: project)
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let pixelWidth = Int((Double(layout.canvasSize.width) * safeScale).rounded())
        let pixelHeight = Int((Double(layout.canvasSize.height) * safeScale).rounded())

        guard let context = makeContext(width: pixelWidth, height: pixelHeight) else {
            throw RenderError.contextCreationFailed
        }
        // Flip to a top-left origin so all layout maths matches Core's coordinate system.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: CGFloat(safeScale), y: -CGFloat(safeScale))
        context.interpolationQuality = .high

        drawBackdrop(project.backdrop, size: layout.canvasSize, in: context)
        drawContent(content, in: layout.contentRect, context: context)

        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func drawBackdrop(_ backdrop: Backdrop, size: PixelSize, in context: CGContext) {
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch backdrop {
        case .none:
            context.clear(bounds)
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(bounds)
        }
    }

    private static func drawContent(_ image: CGImage, in rect: LayoutRect, context: CGContext) {
        let target = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        // Images draw bottom-up; undo the flip locally so content is not mirrored.
        context.saveGState()
        context.translateBy(x: 0, y: target.minY + target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: target)
        context.restoreGState()
    }
}

extension RGBAColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
