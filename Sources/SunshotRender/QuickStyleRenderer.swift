public import CoreGraphics
public import Foundation
public import SunshotCore

/// S16: a quick capture rendered with the default style, through the same `Renderer.render` as preview and export.
public enum QuickStyleRenderer {
    /// The document a capture opens as: the default style (or the plain new document) with `image` as content.
    /// `plainFrame`: a macOS screenshot, which already has its window chrome, gets frame None.
    public static func document(for image: CGImage, style: QuickStyle?, plainFrame: Bool = false) -> EditorDocument {
        var session = EditorSession(document: EditorDocument(project: style?.project ?? Project()))
        session.setContent(image, plainFrame: plainFrame)
        return session.document
    }

    /// `image` styled at 1×: one canvas pixel per captured pixel, so a Retina capture stays sharp without growing.
    /// Throws `ExportError.tooLarge` before allocating anything when the styled canvas would exceed the maximum side
    /// (a huge capture plus padding), like export does.
    public static func render(_ image: CGImage, style: QuickStyle?, plainFrame: Bool = false) throws -> CGImage {
        let document = document(for: image, style: style, plainFrame: plainFrame)
        if let size = EditorSession(document: document).canvasSize,
            max(size.width, size.height) > SunshotDefaults.maxCanvasSide
        {
            throw ExportError.tooLarge(width: size.width, height: size.height)
        }
        guard let output = try Renderer.render(document: document, scale: 1)
        else { throw RenderError.noContent }
        return output
    }

    /// PNG bytes of `render(_:style:)`.
    public static func pngData(_ image: CGImage, style: QuickStyle?, plainFrame: Bool = false) throws -> Data {
        try ImageCodec.pngData(try render(image, style: style, plainFrame: plainFrame))
    }
}
