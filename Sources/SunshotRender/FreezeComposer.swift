public import CoreGraphics
import Foundation
public import SunshotCore

public enum FreezeComposerError: Error, Equatable, Sendable {
    case emptyCrop
    case contextFailed
}

/// Turns a frozen-screen capture into the final image: crops the selected region and draws the quick marks on it.
public enum FreezeComposer {
    /// `frozen` is the whole display; `displaySize` its size in points. `crop` and `marks` are in display points
    /// (top-left origin). The result is `crop` at the display's native pixel density.
    public static func compose(
        frozen: CGImage, displaySize: (width: Double, height: Double), crop: LayoutRect, marks: [Annotation]
    ) throws -> CGImage {
        guard displaySize.width > 0, displaySize.height > 0 else { throw FreezeComposerError.emptyCrop }
        let sx = Double(frozen.width) / displaySize.width
        let sy = Double(frozen.height) / displaySize.height
        let pixels = CGRect(x: crop.x * sx, y: crop.y * sy, width: crop.width * sx, height: crop.height * sy)
            .integral.intersection(CGRect(x: 0, y: 0, width: frozen.width, height: frozen.height))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1, let cropped = frozen.cropping(to: pixels)
        else { throw FreezeComposerError.emptyCrop }
        let layer = AnnotationLayer(items: marks.filter(\.isValid))
        guard !layer.isEmpty else { return cropped }

        guard
            let context = CGContext(
                data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FreezeComposerError.contextFailed }
        // Top-left, y-down space in image pixels.
        context.translateBy(x: 0, y: CGFloat(cropped.height))
        context.scaleBy(x: 1, y: -1)
        FrameRenderer.drawImage(
            cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height), context: context)
        // Marks are in display points: scale to pixels and move the crop origin to (0, 0).
        context.scaleBy(x: sx, y: sy)
        context.translateBy(x: -pixels.minX / sx, y: -pixels.minY / sy)
        AnnotationRenderer.draw(layer, in: context)
        guard let result = context.makeImage() else { throw FreezeComposerError.contextFailed }
        return result
    }

    /// The marks alone on a transparent picture `size` points big (1 pixel per point): the overlay's live preview,
    /// drawn by the same code as the final image.
    public static func markLayer(_ marks: [Annotation], size: (width: Double, height: Double)) -> CGImage? {
        let layer = AnnotationLayer(items: marks.filter(\.isValid))
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard !layer.isEmpty, width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(layer, in: context)
        return context.makeImage()
    }
}
