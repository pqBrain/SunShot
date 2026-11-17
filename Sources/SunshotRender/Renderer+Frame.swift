public import CoreGraphics
public import SunshotCore

extension Renderer {
    /// Thumbnail for the frame picker: a sample window in `kind`, drawn by the same `render` path (and so the same
    /// `FrameRenderer`) as the canvas, with the document's tokens, corners and UI scale, on a transparent backdrop.
    public static func renderFrameThumbnail(
        _ kind: FrameKind, project: Project, size: PixelSize, content: CGImage? = nil
    ) throws -> CGImage {
        var thumbnail = Project.plain(canvas: .exact(size), backdrop: .none, padding: 16)
        thumbnail.border = project.border
        thumbnail.tokens = project.tokens
        thumbnail.frame = Frame(kind: kind, title: "", uiScale: project.frame.uiScale)
        let sample = try content ?? SampleContent.image(width: 320, height: 200)
        return try render(project: thumbnail, content: sample)
    }
}
