import Foundation
import SunshotRender

/// Memory hygiene. Sunshot can live in the menu bar for days, so what the studio rebuilds on demand (thumbnails,
/// animation frames, the video decoder, cached preview backdrops) is dropped when the studio window closes and when
/// the system reports memory pressure. The document, its history and the preview stay: reopening shows at once.
extension EditorModel {
    /// Drops every derived image the studio can render again. Safe at any time; the next use re-renders.
    public func releaseCachedImages() {
        pause()
        animate.frame = nil
        animate.frameDocument = nil
        animate.videoSource = nil

        layout.thumbnailTask?.cancel()
        layout.thumbnailTask = nil
        layout.pendingThumbnailKey = nil
        layout.thumbnailKey = nil
        layout.thumbnails = [:]
        layout.thumbnailCache = []

        templates.thumbnailTask?.cancel()
        templates.thumbnailTask = nil
        templates.thumbnailKey = nil
        templates.thumbnails = [:]

        FrameThumbnailCache.shared.removeAll()
        Renderer.purgeCaches()
    }

    /// The studio window is showing again: re-renders the layout thumbnails `releaseCachedImages` dropped (the
    /// template pane and the animation frame re-render on their own when their views appear).
    public func studioWillShow() {
        scheduleLayoutThumbnails()
    }
}

/// Calls `onPressure` on the main actor when the system reports memory pressure (warning or critical).
@MainActor
public final class MemoryPressureMonitor {
    private let source: any DispatchSourceMemoryPressure

    public init(onPressure: @escaping @MainActor () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onPressure() } }
        source.activate()
    }

    public func cancel() { source.cancel() }
}
