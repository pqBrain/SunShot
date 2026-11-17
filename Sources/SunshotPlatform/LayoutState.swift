public import AppKit
public import Observation
public import SunshotCore
import SunshotRender
import os

/// The bundled layout presets, loaded once. A catalog that fails to load is logged and shows no layouts (manual
/// position, zoom, rotation and tilt still work); the smoke test fails if it is empty.
@MainActor
public final class LayoutLibrary {
    public static let shared = LayoutLibrary()

    public let catalog: LayoutPresetCatalog?
    private static let logger = Logger(subsystem: "app.sunshot", category: "layout-presets")

    public init(load: () throws -> LayoutPresetCatalog = LayoutPresetCatalog.load) {
        do {
            catalog = try load()
        } catch {
            Self.logger.error("Could not load layout presets: \(String(describing: error), privacy: .public)")
            catalog = nil
        }
    }

    public var presets: [LayoutPreset] { catalog?.presets ?? [] }
}

/// S6 UI state that isn't part of the document: preset thumbnails, the running preset animation, and the
/// guides of the position drag in progress.
@MainActor
@Observable
public final class LayoutState {
    /// Thumbnail per preset id for the current style and content (empty while none are rendered yet).
    public internal(set) var thumbnails: [String: CGImage] = [:]
    /// Guides shown on the mini canvas during a position drag; cleared when the drag ends.
    public internal(set) var guides: [PositionGuide] = []
    /// The transform the preview shows mid-animation (nil when not animating).
    public internal(set) var animatingTransform: ContentTransform?
    /// Frames shown by the last preset animation and how long it ran (for tests and diagnostics).
    public internal(set) var lastAnimation: (frames: [ContentTransform], duration: Duration)?
    /// Whether to skip the preset animation. Defaults to the system's Reduce Motion setting.
    public var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Wait after the last style change before thumbnails re-render.
    public var thumbnailDebounce: Duration = .milliseconds(120)

    public let library: LayoutLibrary
    var drag: PositionDrag?
    var pinch: CanvasPinch?
    var twist: CanvasTwist?
    var paddingDrag: PaddingDrag?
    var tiltDrag: TiltDrag?
    var cornerDragStart: Double?
    var thumbnailKey: LayoutThumbnailKey?
    var pendingThumbnailKey: LayoutThumbnailKey?
    /// The running thumbnail render (await it in tests).
    public internal(set) var thumbnailTask: Task<Void, Never>?
    public internal(set) var animationTask: Task<Void, Never>?
    /// Recently rendered thumbnail sets, so undo / redo of a style change shows thumbnails at once.
    var thumbnailCache: [(key: LayoutThumbnailKey, images: [String: CGImage])] = []
    static let thumbnailCacheLimit = 4

    public init(library: LayoutLibrary = .shared) {
        self.library = library
    }

    public var presets: [LayoutPreset] { library.presets }

    func cachedThumbnails(for key: LayoutThumbnailKey) -> [String: CGImage]? {
        thumbnailCache.first { $0.key == key }?.images
    }

    func storeThumbnails(_ images: [String: CGImage], for key: LayoutThumbnailKey) {
        thumbnailCache.removeAll { $0.key == key }
        thumbnailCache.append((key, images))
        if thumbnailCache.count > Self.thumbnailCacheLimit { thumbnailCache.removeFirst() }
    }
}
