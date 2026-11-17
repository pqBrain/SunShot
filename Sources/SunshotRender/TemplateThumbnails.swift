public import CoreGraphics
public import SunshotCore

/// Live previews for the template gallery and the device picker (S12), all drawn by the one `Renderer.render`.
public enum TemplateThumbnails {
    /// Long side of a gallery card preview in pixels.
    public static let defaultMaxSide = 240
    /// Long side of the generated sample content (laid out at the template's full sample size).
    static let sampleLongSide = 480

    /// The document `template` would make of `document`: the template's style with the document's content.
    public static func preview(_ template: DocumentTemplate, of document: EditorDocument) -> EditorDocument {
        var variant = document
        variant.project = EditorSession.project(template, keeping: document.project)
        return variant
    }

    /// The gallery card for `template`: the current content in the template, or sample content when the
    /// document is empty, fitted into `maxSide`.
    public static func render(
        _ template: DocumentTemplate, document: EditorDocument, maxSide: Int = defaultMaxSide
    ) throws -> CGImage? {
        let variant = preview(template, of: document)
        if let size = variant.contentPixelSize {
            let canvas = CanvasLayout.compute(contentSize: size, project: variant.project).canvasSize
            return try Renderer.render(document: variant, scale: fitScale(canvas, maxSide: maxSide))
        }
        return try renderSample(project: variant.project, contentSize: template.sampleSize(), maxSide: maxSide)
    }

    /// Sample content of `contentSize` (drawn small, laid out full size) in `project`, fitted into `maxSide`.
    public static func renderSample(project: Project, contentSize: PixelSize, maxSide: Int) throws -> CGImage {
        let factor = Double(sampleLongSide) / Double(max(contentSize.width, contentSize.height))
        let sample = try SampleContent.image(
            width: max(1, Int((Double(contentSize.width) * factor).rounded())),
            height: max(1, Int((Double(contentSize.height) * factor).rounded())))
        let canvas = CanvasLayout.compute(contentSize: contentSize, project: project).canvasSize
        return try Renderer.render(
            project: project, content: sample, scale: fitScale(canvas, maxSide: maxSide), layoutSize: contentSize)
    }

    /// A device picker tile: sample content on `model` in `finish`, on a transparent backdrop without shadow.
    public static func renderDevice(
        _ model: DeviceModel, finish: String, landscape: Bool = false, maxSide: Int = 96
    ) throws -> CGImage {
        var project = Project.plain(backdrop: .none, padding: 0)
        project.frame.device = DeviceSelection(model: model.id, finish: finish, landscape: landscape)
        return try renderSample(
            project: project, contentSize: model.oriented(landscape: landscape).recommendedSize, maxSide: maxSide)
    }

    static func fitScale(_ canvas: PixelSize, maxSide: Int) -> Double {
        Double(max(maxSide, 1)) / Double(max(canvas.width, canvas.height))
    }
}
