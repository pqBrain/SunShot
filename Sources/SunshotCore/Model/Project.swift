/// How the canvas size is chosen.
public enum CanvasSpec: Codable, Hashable, Sendable {
    /// Canvas follows the content size plus padding.
    case auto
    /// Fixed aspect ratio (width / height); the content is fitted inside with padding.
    case ratio(Double)
    /// Exact pixel size (e.g. store screenshots).
    case exact(PixelSize)
}

public enum Backdrop: Codable, Hashable, Sendable {
    case none
    case solid(RGBAColor)
}

/// The whole editable document. Value type: every mutation produces a new value, which makes undo trivial.
public struct Project: Codable, Hashable, Sendable {
    public var canvas: CanvasSpec
    public var backdrop: Backdrop
    /// Padding around the content as a fraction of the content's longer edge (0...0.5).
    public var padding: Double

    public init(canvas: CanvasSpec = .auto, backdrop: Backdrop = .solid(.defaultBackdrop), padding: Double = 0.08) {
        self.canvas = canvas
        self.backdrop = backdrop
        self.padding = min(max(padding, 0), 0.5)
    }
}

extension RGBAColor {
    /// Sunshot's default backdrop: a warm off-white.
    public static let defaultBackdrop = RGBAColor(red: 0.96, green: 0.94, blue: 0.91)
}
