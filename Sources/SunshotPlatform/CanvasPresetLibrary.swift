public import SunshotCore
import os

/// The bundled canvas size presets, loaded once. A catalog that fails to load is logged and shows no presets
/// (Auto and custom sizes still work); the smoke test fails if it is empty, so that can't ship silently.
@MainActor
public final class CanvasPresetLibrary {
    public static let shared = CanvasPresetLibrary()

    public let catalog: CanvasPresetCatalog?
    private static let logger = Logger(subsystem: "app.sunshot", category: "canvas-presets")

    public init(load: () throws -> CanvasPresetCatalog = CanvasPresetCatalog.load) {
        do {
            catalog = try load()
        } catch {
            Self.logger.error("Could not load canvas presets: \(String(describing: error), privacy: .public)")
            catalog = nil
        }
    }

    public var presets: [CanvasPreset] { catalog?.presets ?? [] }

    /// Search results grouped in display order; empty when nothing matches.
    public func sections(matching query: String) -> [(group: CanvasPresetGroup, presets: [CanvasPreset])] {
        catalog?.sections(matching: query) ?? []
    }
}
