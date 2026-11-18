public import SunshotCore

/// Annotate mode copy (S9).
extension UIStrings {
    public static let annotate = "Annotate"
    /// S17-AC3: the toolbar's Annotate button.
    public static let hideAnnotationBar = "Hide the annotation bar"
    public static let showAnnotationBar = "Show the annotation bar"
    public static let doneAnnotating = "Done"
    public static let doneAnnotatingAccessibility = "Leave Annotate mode, Esc"
    public static let clearAnnotations = "Clear Annotations"
    /// S17-AC8: the annotation bar's short label (the menu keeps "Clear Annotations").
    public static let clearAnnotationsShort = "Clear"
    public static let deleteSelection = "Delete"
    public static let annotationColor = "Colour"
    public static let customAnnotationColor = "Custom colour"
    public static let annotationSize = "Size"
    public static let lineStyle = "Line style"
    public static let fill = "Fill"
    public static let stickers = "Stickers…"
    public static let redactionMode = "Redaction"
    public static let stepFormat = "Step labels"
    public static let textPlaceholder = "Type text"
    public static let toolPalette = "Annotation tools"
    public static let annotationCanvas = "Annotation canvas"

    public static func toolName(_ tool: AnnotationTool) -> String {
        switch tool {
        case .select: "Select"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .text: "Text"
        case .step: "Steps"
        case .redact: "Redact"
        case .sticker: "Sticker"
        }
    }

    /// "Pen, P" — help text and VoiceOver label.
    public static func toolLabel(_ tool: AnnotationTool) -> String {
        guard let key = tool.shortcut else { return toolName(tool) + ", ⌥⌘S" }
        return toolName(tool) + ", " + key.uppercased()
    }

    public static func toolSymbol(_ tool: AnnotationTool) -> String {
        switch tool {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .step: "1.circle"
        case .redact: "eye.slash"
        case .sticker: "face.smiling"
        }
    }

    public static func sizeName(_ size: AnnotationSize) -> String {
        switch size {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    public static func lineStyleName(_ style: AnnotationLineStyle) -> String {
        switch style {
        case .solid: "Solid, ⇧1"
        case .dashed: "Dashed, ⇧2"
        case .dotted: "Dotted, ⇧3"
        }
    }

    public static func redactionName(_ mode: RedactionMode) -> String {
        switch mode {
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        }
    }

    public static func stepFormatName(_ format: StepFormat) -> String {
        switch format {
        case .numbers: "1 2 3"
        case .letters: "A B C"
        }
    }

    public static func alignmentName(_ alignment: AnnotationTextAlignment) -> String {
        switch alignment {
        case .left: "Align left"
        case .center: "Align centre"
        case .right: "Align right"
        }
    }
}
