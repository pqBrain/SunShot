public import SunshotCore

/// S16: the annotation bar sits at the top of the canvas whenever there is a screenshot, so a tool is one click
/// away. Picking a tool from it enters Annotate mode; Done leaves it and the canvas can be moved again.
extension EditorModel {
    /// The bar shows for screenshots outside Animate mode; code snippets have no annotations.
    public var showsAnnotationBar: Bool { hasContent && !isSnippet && !animate.isActive }

    /// Whether the bar's tools can be used (see `canAnnotate` for content that can't be annotated yet).
    public var isAnnotationBarEnabled: Bool { annotate.isActive || canAnnotate }

    /// A tool picked from the always-visible bar: enters Annotate mode (when possible) and selects it. The sticker
    /// tool opens its picker instead; picking an emoji selects the tool.
    public func pickAnnotationTool(_ tool: AnnotationTool) {
        setAnnotateMode(true)
        guard annotate.isActive else { return }
        if tool == .sticker {
            annotate.showsStickerPicker.toggle()
        } else {
            selectTool(tool)
        }
    }
}
