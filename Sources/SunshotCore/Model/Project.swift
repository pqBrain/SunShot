/// How the canvas size is chosen.
public enum CanvasSpec: Codable, Hashable, Sendable {
    /// Canvas follows the content size plus padding.
    case auto
    /// Fixed aspect ratio (width / height); the canvas grows around the unscaled content.
    case ratio(Double)
    /// Exact pixel size (e.g. store screenshots); content is scaled to fit inside the padding.
    case exact(PixelSize)
}

public enum Backdrop: Codable, Hashable, Sendable {
    case none
    case solid(RGBAColor)
}

/// The style of a document (everything except the content image). Value type, so undo is trivial.
public struct Project: Codable, Hashable, Sendable {
    public var canvas: CanvasSpec
    public var backdrop: Backdrop
    /// Padding around the content on every side, in canvas pixels (0...`SunshotDefaults.maxPadding`).
    public var padding: Double

    public init(
        canvas: CanvasSpec = .auto,
        backdrop: Backdrop = .solid(SunshotDefaults.backdropColor),
        padding: Double = SunshotDefaults.padding
    ) {
        self.canvas = canvas
        self.backdrop = backdrop
        self.padding = padding.isFinite ? min(max(padding, 0), SunshotDefaults.maxPadding) : SunshotDefaults.padding
    }
}
