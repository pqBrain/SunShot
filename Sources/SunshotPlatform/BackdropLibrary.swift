public import CoreGraphics
public import SunshotCore
import SunshotRender
import os

/// Sunshot's swatches, gradient presets and wallpapers, with thumbnails drawn by the same backdrop renderer as
/// the canvas. Loaded once; thumbnails are cached.
@MainActor
public final class BackdropLibrary {
    public static let shared = BackdropLibrary()

    /// Thumbnail size in pixels (2× of the 16:10 tiles in the inspector).
    public static let thumbnailSize = PixelSize(width: 112, height: 70)
    /// Stop-bar strip size in pixels.
    public static let stopBarSize = PixelSize(width: 480, height: 32)

    public let swatchGroups: [SwatchGroup]
    public let gradientPresets: [GradientPreset]
    public let wallpapers: [Wallpaper]

    private var thumbnails: [String: CGImage] = [:]
    private var stopBar: (spec: GradientSpec, image: CGImage)?
    private static let logger = Logger(subsystem: "app.sunshot", category: "backdrop-library")

    public init(
        swatchGroups: () throws -> [SwatchGroup] = BackdropCatalog.swatchGroups,
        gradientPresets: () throws -> [GradientPreset] = BackdropCatalog.gradientPresets,
        wallpapers: () throws -> [Wallpaper] = BackdropCatalog.wallpapers
    ) {
        self.swatchGroups = Self.load("swatches", swatchGroups)
        self.gradientPresets = Self.load("gradient presets", gradientPresets)
        self.wallpapers = Self.load("wallpapers", wallpapers)
    }

    private static func load<T>(_ what: String, _ loader: () throws -> [T]) -> [T] {
        do {
            return try loader()
        } catch {
            logger.error("Could not load \(what, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    public var swatches: [Swatch] { swatchGroups.flatMap(\.swatches) }

    public func thumbnail(for preset: GradientPreset) -> CGImage? {
        thumbnail(key: "gradient:\(preset.id)", backdrop: .gradient(preset.spec))
    }

    public func thumbnail(for wallpaper: Wallpaper) -> CGImage? {
        thumbnail(key: "wallpaper:\(wallpaper.id)", backdrop: .image(.wallpaper(wallpaper)))
    }

    /// The gradient's stops laid out left → right (linear, 90°), for the stop editor bar.
    public func stopBarImage(for spec: GradientSpec) -> CGImage? {
        if let stopBar, stopBar.spec == spec { return stopBar.image }
        let strip = GradientSpec(kind: .linear, angle: 90, stops: spec.stops)
        guard let image = try? Renderer.renderBackdrop(.gradient(strip), size: Self.stopBarSize) else { return nil }
        stopBar = (spec, image)
        return image
    }

    private func thumbnail(key: String, backdrop: Backdrop) -> CGImage? {
        if let cached = thumbnails[key] { return cached }
        guard let image = try? Renderer.renderBackdrop(backdrop, size: Self.thumbnailSize) else { return nil }
        thumbnails[key] = image
        return image
    }
}
