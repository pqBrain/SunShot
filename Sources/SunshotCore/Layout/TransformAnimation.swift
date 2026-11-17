/// Timing of the layout-preset transition: 300 ms, cubic ease-in-out. Only the preview animates; the document
/// holds the target from the start, so an export started mid-animation always renders the final transform.
public enum TransformAnimation {
    public static let duration: Duration = .milliseconds(300)

    /// Cubic ease-in-out on 0…1 (clamped; non-finite → 1).
    public static func easeInOut(_ rawT: Double) -> Double {
        guard rawT.isFinite else { return 1 }
        let t = min(max(rawT, 0), 1)
        if t < 0.5 { return 4 * t * t * t }
        let u = -2 * t + 2
        return 1 - u * u * u / 2
    }

    /// The transform shown `elapsed` into an animation from `from` to `to`.
    public static func frame(from: ContentTransform, to: ContentTransform, elapsed: Duration) -> ContentTransform {
        from.interpolated(to: to, t: easeInOut(elapsed / duration))
    }
}
