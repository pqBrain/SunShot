public import CoreGraphics

/// Deterministic synthetic content used by the smoke test, previews and snapshot tests.
public enum SampleContent {
    /// A fake "app window": white body, a dark title strip and three coloured blocks.
    public static func image(width: Int = 640, height: Int = 400) throws -> CGImage {
        guard let context = Renderer.makeContext(width: width, height: height) else {
            throw RenderError.contextCreationFailed
        }
        let w = CGFloat(width)
        let h = CGFloat(height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(CGColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: h * 0.88, width: w, height: h * 0.12))
        let blocks: [(CGFloat, CGFloat, CGFloat)] = [(0.93, 0.36, 0.33), (0.98, 0.75, 0.2), (0.3, 0.72, 0.45)]
        for (index, color) in blocks.enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            let x = w * (0.08 + CGFloat(index) * 0.3)
            context.fill(CGRect(x: x, y: h * 0.12, width: w * 0.24, height: h * 0.6))
        }
        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }
}
