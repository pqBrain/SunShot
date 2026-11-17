public import CoreGraphics
import SunshotCore

/// S15: cuts a solid-colour border off a pasted or captured image (see `BorderTrim`).
public enum ImageTrimmer {
    /// The image without its solid border, or nil when it has none worth trimming.
    public static func trimmed(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let context = Renderer.makeContext(width: width, height: height) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        // The bitmap stores rows top to bottom, possibly padded; pack them for `BorderTrim`.
        let stride = context.bytesPerRow
        let source = data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        bytes.withUnsafeMutableBufferPointer { packed in
            guard let base = packed.baseAddress else { return }
            for row in 0..<height {
                (base + row * rowBytes).update(from: source + row * stride, count: rowBytes)
            }
        }
        guard let rect = BorderTrim.trimRect(rgba: bytes, width: width, height: height) else { return nil }
        return image.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
    }
}
