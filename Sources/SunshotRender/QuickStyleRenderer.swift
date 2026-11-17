public import CoreGraphics
public import Foundation
public import SunshotCore

/// S16: a quick capture rendered with the default style, through the same `Renderer.render` as preview and export.
public enum QuickStyleRenderer {
    /// The document a capture opens as: the default style (or the plain new document) with `image` as content.
    public static func document(for image: CGImage, style: QuickStyle?) -> EditorDocument {
        var session = EditorSession(document: EditorDocument(project: style?.project ?? Project()))
        session.setContent(image)
        return session.document
    }

    /// `image` styled at 1×: one canvas pixel per captured pixel, so a Retina capture stays sharp without growing.
    public static func render(_ image: CGImage, style: QuickStyle?) throws -> CGImage {
        guard let output = try Renderer.render(document: document(for: image, style: style), scale: 1)
        else { throw RenderError.noContent }
        return output
    }

    /// PNG bytes of `render(_:style:)`.
    public static func pngData(_ image: CGImage, style: QuickStyle?) throws -> Data {
        try ImageCodec.pngData(try render(image, style: style))
    }
}
