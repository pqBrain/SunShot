public import CoreGraphics
public import Foundation
public import Observation
import SunshotRender

/// S13 UI state that isn't part of the document: Animate mode, the playhead, playback, the clip selection, the
/// frame shown at the playhead and a running video export.
@MainActor
@Observable
public final class AnimateState {
    public internal(set) var isActive = false
    /// Seconds from the start of the animation.
    public internal(set) var playhead: Double = 0
    public internal(set) var isPlaying = false
    public var selectedClipID: UUID?
    /// The canvas at the playhead, rendered by `Renderer.render` at preview scale (nil until rendered).
    public internal(set) var frame: CGImage?
    /// The document `frame` was rendered from, so a stale frame is never shown after an edit.
    var frameDocument: EditorDocument?
    var frameTime: Double = -1
    var frameGeneration = 0
    /// The running playback loop (await it in tests).
    public internal(set) var playbackTask: Task<Void, Never>?

    /// Decoder for the current video content (opened on first use, replaced when the video changes).
    var videoSource: (id: UUID, source: VideoFrameSource)?

    /// Export sheet and progress.
    public var showsExportSheet = false
    public internal(set) var isExporting = false
    public internal(set) var exportProgress: Double = 0
    /// The running export (cancel it to stop).
    var exportWork: Task<Void, any Error>?

    /// Pause between playback frames: caps the preview at ~60 fps; slower renders simply skip ahead.
    public var frameInterval: Duration = .milliseconds(16)

    public init() {}
}
