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
    public static func render(_ image: CGImage, style: QuickStyle?, plainFrame: Bool = false) throws -> CGImage {
        let document = document(for: image, style: style, plainFrame: plainFrame)
        guard let output = try Renderer.render(document: document, scale: 1)
        else { throw RenderError.noContent }
        return output
    }

    /// PNG bytes of `render(_:style:)`.
    public static func pngData(_ image: CGImage, style: QuickStyle?, plainFrame: Bool = false) throws -> Data {
        try ImageCodec.pngData(try render(image, style: style, plainFrame: plainFrame))
    }
}
