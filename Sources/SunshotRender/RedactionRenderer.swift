import CoreGraphics
import Foundation
import SunshotCore

/// Blur / pixelate redaction. It rewrites the content pixels *before* the content is drawn: inside each redaction
/// region the image is replaced (not overlaid) with block averages, so no original pixel value reaches the preview
/// or the export, also where the content is translucent.
enum RedactionRenderer {
    /// `image` with every redaction of `layer` applied, or `image` itself when there are none.
    static func apply(_ layer: AnnotationLayer, to image: CGImage) -> CGImage {
        let redactions = layer.items.filter { $0.kind == .redact && $0.isValid }
        guard !redactions.isEmpty else { return image }
        let width = image.width
        let height = image.height
        guard let context = Renderer.makeContext(width: width, height: height) else { return image }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        drawImage(image, in: full, context: context)
        for redaction in redactions {
            draw(redaction, source: image, in: context)
        }
        return context.makeImage() ?? image
    }

    /// Size in content pixels of one averaged block.
    static func blockSize(for annotation: Annotation) -> Double {
        let base = max(AnnotationDefaults.minimumRedactionBlock, annotation.lineWidth * 2)
        return annotation.redaction == .blur ? base * 2 : base
    }

    private static func draw(_ annotation: Annotation, source: CGImage, in context: CGContext) {
        let box = AnnotationRenderer.cgRect(annotation.bounds)
        var transform = CGAffineTransform.identity
        if annotation.rotation != 0 {
            let center = annotation.center
            transform = transform.translatedBy(x: center.x, y: center.y)
                .rotated(by: annotation.rotation * .pi / 180)
                .translatedBy(x: -center.x, y: -center.y)
        }
        let shape = CGPath(rect: box, transform: &transform)
        let region = shape.boundingBoxOfPath.integral.intersection(
            CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard !region.isNull, region.width >= 1, region.height >= 1,
            let averaged = blockAverages(of: source, in: region, block: blockSize(for: annotation))
        else { return }
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setBlendMode(.copy)
        context.interpolationQuality = annotation.redaction == .pixelate ? .none : .high
        drawImage(averaged, in: region, context: context)
        context.restoreGState()
    }

    /// The pixels of `region` reduced to one average per block (premultiplied RGBA), as a small image.
    static func blockAverages(of image: CGImage, in region: CGRect, block: Double) -> CGImage? {
        let width = Int(region.width)
        let height = Int(region.height)
        guard width > 0, height > 0, let crop = image.cropping(to: region),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let columns = max(1, Int((Double(width) / block).rounded()))
        let rows = max(1, Int((Double(height) / block).rounded()))
        var sums = [UInt64](repeating: 0, count: columns * rows * 4)
        var counts = [UInt64](repeating: 0, count: columns * rows)
        for y in 0..<height {
            let row = y * rows / height
            for x in 0..<width {
                let bin = row * columns + x * columns / width
                let offset = (y * width + x) * 4
                for channel in 0..<4 { sums[bin * 4 + channel] += UInt64(pixels[offset + channel]) }
                counts[bin] += 1
            }
        }
        var averages = [UInt8](repeating: 0, count: columns * rows * 4)
        for bin in 0..<(columns * rows) where counts[bin] > 0 {
            for channel in 0..<4 {
                averages[bin * 4 + channel] = UInt8((sums[bin * 4 + channel] + counts[bin] / 2) / counts[bin])
            }
        }
        guard let provider = CGDataProvider(data: Data(averages) as CFData) else { return nil }
        // The pixel buffer rows run top-down in memory, matching a CGImage's first row = top.
        return CGImage(
            width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Draws `image` upright into `rect` of a y-down context.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }
}
