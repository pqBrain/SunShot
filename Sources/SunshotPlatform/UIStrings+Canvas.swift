public import SunshotCore

/// S4: canvas size and export options copy and accessibility labels.
extension UIStrings {
    public static let canvasSection = "Canvas"
    public static let canvasSize = "Canvas size"
    public static let auto = "Auto"
    public static let autoDescription = "Fits the image"
    public static let searchSizes = "Search sizes"
    public static let noSizesMatch = "No sizes match"
    public static let customSize = "Custom size"
    public static let widthField = "W"
    public static let heightField = "H"
    public static let widthAccessibility = "Custom width in pixels, empty for Auto"
    public static let heightAccessibility = "Custom height in pixels, empty for Auto"
    public static let setCustomSize = "Set"
    public static let customSizeInvalid = "Enter 1–16384"
    public static let clearSearch = "Clear search"

    public static let exportOptions = "Export options"
    public static let exportOptionsAccessibility = "Export options: format and size"
    public static let formatPicker = "Format"
    public static let scalePicker = "Size"
    public static let resolutionRow = "Resolution"
    public static let formatRow = "Format"
    public static let fileNameRow = "File name"
    public static let exportNow = "Export…"
    public static let nativeSizeHint = "Store sizes always export at their exact pixel size."
    public static let jpegNoTransparency = "JPEG doesn't support transparency"
    public static let exportTooLarge = "This size is too large to export (max 16384 px per side)"

    public static func formatUnavailable(_ format: ExportFormat) -> String {
        "This Mac can't write \(format.displayName) files"
    }

    /// `2256 × 1456`.
    public static func pixelSize(width: Int, height: Int) -> String { "\(width) × \(height)" }

    /// What the Canvas button shows: `Auto`, `16:9 Widescreen`, `iPhone 6.7″`, `Custom 800 × Auto`.
    public static func canvasValue(_ canvas: CanvasSpec) -> String {
        switch canvas {
        case .auto: return auto
        case .ratio(let ratio): return "\(CanvasPreset.format(ratio)):1"
        case .exact(let size): return pixelSize(width: size.width, height: size.height)
        case .preset(let preset): return preset.exactSize == nil ? "\(preset.ratioLabel) \(preset.name)" : preset.name
        case .custom(let custom):
            let width = custom.width.map(String.init) ?? auto
            let height = custom.height.map(String.init) ?? auto
            return "Custom \(width) × \(height)"
        }
    }

    /// VoiceOver label for a preset tile: `16:9 Widescreen, 1920 by 1080`.
    public static func presetAccessibility(_ preset: CanvasPreset, size: PixelSize?) -> String {
        let title = preset.exactSize == nil ? "\(preset.ratioLabel) \(preset.name)" : preset.name
        guard let size else { return title }
        return "\(title), \(size.width) by \(size.height)"
    }

    /// VoiceOver label for the Auto tile: `Auto, fits the image, 1128 by 728`.
    public static func presetAccessibilityAuto(size: PixelSize?) -> String {
        let title = "\(auto), \(autoDescription.lowercased())"
        guard let size else { return title }
        return "\(title), \(size.width) by \(size.height)"
    }

    public static func canvasSizeAccessibility(_ canvas: CanvasSpec, size: PixelSize?) -> String {
        let value = canvasValue(canvas)
        guard let size else { return "\(canvasSize): \(value)" }
        return "\(canvasSize): \(value), \(size.width) by \(size.height) pixels"
    }
}
