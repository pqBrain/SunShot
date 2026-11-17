public import CoreGraphics
public import SunshotCore

/// The S11 hook into the single render path: snippet content is drawn at the output density, then goes through
/// the same backdrop / padding / border / shadow / canvas pipeline as an image.
extension Renderer {
    /// Renders `project` with `snippet` as its content at `scale`.
    public static func render(
        project: Project, snippet: CodeSnippet, media: [String: MediaAsset] = [:], scale: Double = 1,
        grid: TransparencyGrid? = nil
    ) throws -> CGImage {
        let prepared = CodeSnippetRenderer.prepare(snippet)
        let contentSize = prepared.layout.size
        let layout = CanvasLayout.compute(contentSize: contentSize, project: project)
        let content = try prepared.image(scale: contentDensity(scale: scale, layout: layout))
        return try render(
            project: project, content: content, contentSize: contentSize, media: media, scale: scale, grid: grid)
    }

    /// Output pixels per content pixel: the export scale times any exact-canvas style scale.
    static func contentDensity(scale: Double, layout: CanvasLayout) -> Double {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let style = layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1
        return safeScale * style
    }
}

extension EditorDocument {
    /// Size of the content at 1× (the snippet's laid-out size, or the image's pixel size); nil when empty.
    public var contentPixelSize: PixelSize? {
        if let snippet { return CodeSnippetRenderer.layout(of: snippet).size }
        return content?.pixelSize
    }
}
