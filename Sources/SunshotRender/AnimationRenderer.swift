public import CoreGraphics
public import SunshotCore

/// S13: one moment of an animation. Never draws anything itself: it builds the document as it looks at `time`
/// (interpolated transform; the video's frame as content) and hands it to `Renderer.render(document:)`, so
/// playback preview, video export and still export share one drawing path.
public enum AnimationRenderer {
    /// `document` at `time` seconds: its transform replaced by the timeline's, and — for video content — its
    /// content replaced by `videoFrame`. Style, media and history are untouched.
    public static func document(_ document: EditorDocument, at time: Double, videoFrame: CGImage?) -> EditorDocument {
        var frame = document
        let start = document.project.placement.transform
        frame.project.placement.transform = document.project.timeline.transform(at: time, from: start)
        if let videoFrame, let video = document.activeVideo {
            frame.content = ContentImage(videoFrame, id: video.posterID)
        }
        return frame
    }

    /// Renders the frame at `time` through `Renderer.render(document:)`.
    public static func render(
        _ document: EditorDocument, at time: Double, videoFrame: CGImage? = nil, scale: Double = 1,
        showsTransparencyGrid: Bool = false, grid: TransparencyGrid = .standard
    ) throws -> CGImage? {
        try Renderer.render(
            document: self.document(document, at: time, videoFrame: videoFrame), scale: scale,
            showsTransparencyGrid: showsTransparencyGrid, grid: grid)
    }

    /// Length of the animation (or video) in seconds, capped at two minutes.
    public static func duration(of document: EditorDocument) -> Double {
        document.project.timeline.duration(contentDuration: document.activeVideo?.duration)
    }

    /// The video export plan for `document`, or nil when it has no content.
    public static func exportPlan(for document: EditorDocument) -> VideoExportPlan? {
        guard let contentSize = document.contentPixelSize else { return nil }
        let canvas = CanvasLayout.compute(contentSize: contentSize, project: document.project).canvasSize
        return VideoExportPlan.make(
            canvasSize: canvas, options: document.project.timeline.video, duration: duration(of: document),
            transparent: document.project.hasTransparentBackdrop)
    }
}
