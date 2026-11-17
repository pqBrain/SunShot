public import SunshotCore

/// S16: what the screenshot side of a document holds while the code side is shown, so switching Screenshot ⇄ Code
/// brings each back as it was.
public struct ImageContentStash: Equatable, Sendable {
    public var content: ContentImage
    public var crop: CropRect?
    public var video: VideoContent?
    public var slots: [Int: ContentImage]
    public var annotations: AnnotationLayer?
}

/// S16: switching the document between its screenshot and its code snippet. Each switch is one undo step; the style
/// (backdrop, frame, shadow…) is shared by both.
extension EditorSession {
    public static let showCodeActionName = "Switch to Code"
    public static let showScreenshotActionName = "Switch to Screenshot"

    /// The image side of the document, or nil when it has no image.
    public var imageStash: ImageContentStash? {
        guard let content = document.content else { return nil }
        return ImageContentStash(
            content: content, crop: document.crop, video: document.video, slots: document.slots,
            annotations: document.project.annotationLayer)
    }

    /// Shows `snippet` instead of the image (whose parts the caller keeps from `imageStash`).
    public mutating func showCode(_ snippet: CodeSnippet) {
        history.applyIfChanged(Self.showCodeActionName) {
            $0.content = nil
            $0.crop = nil
            $0.video = nil
            $0.slots = [:]
            $0.project.annotationLayer = nil
            $0.snippet = snippet
        }
    }

    /// Shows `stash` again instead of the snippet; with no stash the document becomes empty, ready for an image.
    public mutating func showScreenshot(_ stash: ImageContentStash?) {
        history.applyIfChanged(Self.showScreenshotActionName) {
            $0.snippet = nil
            $0.content = stash?.content
            $0.crop = stash?.crop
            $0.video = stash?.video
            $0.slots = stash?.slots ?? [:]
            $0.project.annotationLayer = stash?.annotations
        }
    }
}
