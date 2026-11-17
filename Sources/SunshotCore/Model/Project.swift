/// How the canvas size is chosen.
public enum CanvasSpec: Codable, Hashable, Sendable {
    /// Canvas follows the content size plus padding.
    case auto
    /// Fixed aspect ratio (width / height); the canvas grows around the unscaled content.
    case ratio(Double)
    /// Exact pixel size: the padded content is scaled uniformly to fit and exports ignore the scale choice.
    case exact(PixelSize)
    /// A catalog preset (kept whole so a saved document doesn't depend on the catalog version).
    case preset(CanvasPreset)
    /// Custom W×H at 1×; a nil side follows the Auto canvas's ratio. Both nil behaves like `auto`.
    case custom(CustomCanvasSize)
}

/// User-entered canvas size; each side is 1…`SunshotDefaults.maxCanvasSide` or nil (Auto).
public struct CustomCanvasSize: Codable, Hashable, Sendable {
    public let width: Int?
    public let height: Int?

    public init(width: Int?, height: Int?) {
        self.width = width
        self.height = height
    }
}

extension CanvasSpec {
    /// Store presets and exact sizes export at their own pixel size; the scale choice doesn't apply.
    public var nativeSize: PixelSize? {
        switch self {
        case .exact(let size): size
        case .preset(let preset): preset.exactSize
        case .auto, .ratio, .custom: nil
        }
    }

    /// The selected preset, if any.
    public var preset: CanvasPreset? {
        if case .preset(let preset) = self { return preset }
        return nil
    }
}

/// The style of a document (everything except the content image). Value type, so undo is trivial.
public struct Project: Codable, Hashable, Sendable {
    public var canvas: CanvasSpec
    /// Active backdrop type plus the last-used value of each type.
    public var backdropSettings: BackdropSettings
    /// Padding around the content on every side, in canvas pixels (0...`SunshotDefaults.maxPadding`).
    public var padding: Double
    public var border: Border
    public var shadow: Shadow
    /// Format and scale chosen in the export options.
    public var export: ExportOptions
    /// Annotations (S9). Optional so documents without the key decode and a document without annotations encodes
    /// exactly as before; read and write it through `annotations`.
    public var annotationLayer: AnnotationLayer?

    public init(
        canvas: CanvasSpec = .auto,
        backdrop: Backdrop = .solid(SunshotDefaults.backdropColor),
        padding: Double = SunshotDefaults.padding,
        border: Border = Border(),
        shadow: Shadow = Shadow(),
        export: ExportOptions = ExportOptions()
    ) {
        self.canvas = canvas
        var settings = BackdropSettings()
        settings.backdrop = backdrop
        self.backdropSettings = settings
        self.border = border
        self.shadow = shadow
        self.export = export
        self.padding = padding.isFinite ? min(max(padding, 0), SunshotDefaults.maxPadding) : SunshotDefaults.padding
    }
}

extension Project {
    /// The backdrop being drawn. Setting it selects that type and remembers its value for later switches.
    public var backdrop: Backdrop {
        get { backdropSettings.backdrop }
        set { backdropSettings.backdrop = newValue }
    }

    /// No rounding and no shadow: the S1 look, used where tests need content pixels untouched.
    public static func plain(
        canvas: CanvasSpec = .auto, backdrop: Backdrop = .solid(SunshotDefaults.backdropColor),
        padding: Double = SunshotDefaults.padding
    ) -> Project {
        Project(
            canvas: canvas, backdrop: backdrop, padding: padding, border: Border(style: .sharp),
            shadow: Shadow(style: .none))
    }
}
