public import Foundation

/// Image file formats. Whether one can actually be written is checked at runtime (see `ImageCodec`).
public enum ExportFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case png, jpeg, heic, webp

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .webp: "WebP"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .webp: "webp"
        }
    }

    /// Uniform type identifier used by ImageIO.
    public var typeIdentifier: String {
        switch self {
        case .png: "public.png"
        case .jpeg: "public.jpeg"
        case .heic: "public.heic"
        case .webp: "org.webmproject.webp"
        }
    }

    public var supportsTransparency: Bool { self != .jpeg }
}

/// Export scale: a multiple of the canvas, or a fixed long edge (4K = 3840 px, 6K = 6144 px).
public enum ExportScale: String, Codable, CaseIterable, Hashable, Sendable {
    case x1 = "1x"
    case x2 = "2x"
    case k4 = "4k"
    case k6 = "6k"

    /// `{SCALE}` in file names: `1x`, `2x`, `4k`, `6k`.
    public var token: String { rawValue }

    public var displayName: String {
        switch self {
        case .x1: "1×"
        case .x2: "2×"
        case .k4: "4K"
        case .k6: "6K"
        }
    }

    /// For VoiceOver: "2 times", "4K".
    public var spokenName: String {
        switch self {
        case .x1: "1 times"
        case .x2: "2 times"
        case .k4: "4K"
        case .k6: "6K"
        }
    }

    /// Fixed long edge in pixels, for 4K / 6K.
    public var longEdge: Int? {
        switch self {
        case .x1, .x2: nil
        case .k4: 3840
        case .k6: 6144
        }
    }

    /// Render scale for a canvas of `canvas` pixels at 1×.
    public func factor(for canvas: PixelSize) -> Double {
        switch self {
        case .x1: return 1
        case .x2: return 2
        case .k4, .k6:
            let edge = Double(longEdge ?? 0)
            return edge / Double(max(canvas.width, canvas.height))
        }
    }
}

/// What the export options popover edits. Stored in the document.
public struct ExportOptions: Codable, Hashable, Sendable {
    public var format: ExportFormat
    public var scale: ExportScale

    public init(format: ExportFormat = SunshotDefaults.exportFormat, scale: ExportScale = SunshotDefaults.exportScale) {
        self.format = format
        self.scale = scale
    }
}

/// The resolved pixel size of an export.
public struct ExportPlan: Hashable, Sendable {
    /// Canvas size at 1×.
    public let canvasSize: PixelSize
    /// Multiplier from canvas to output pixels.
    public let renderScale: Double
    /// Output width and height (not clamped: may exceed the limit, see `isTooLarge`).
    public let width: Int
    public let height: Int
    /// True for store presets / exact sizes, which always export at their own size.
    public let isNativeSize: Bool

    /// Plans an export of `canvas` at `scale`; `nativeSize` canvases ignore the scale.
    public init(canvas: PixelSize, scale: ExportScale, isNativeSize: Bool = false) {
        canvasSize = canvas
        self.isNativeSize = isNativeSize
        renderScale = isNativeSize ? 1 : scale.factor(for: canvas)
        width = Self.scaled(canvas.width, by: renderScale)
        height = Self.scaled(canvas.height, by: renderScale)
    }

    /// The single rounding rule shared with the renderer.
    public static func scaled(_ length: Int, by scale: Double) -> Int {
        Int(saturatingLength: Double(length) * scale)
    }

    public var outputSize: PixelSize { PixelSize(width: width, height: height) }

    /// Larger than `SunshotDefaults.maxCanvasSide` on either side: export is refused, never attempted.
    public var isTooLarge: Bool { max(width, height) > SunshotDefaults.maxCanvasSide }
}

public enum ExportError: Error, Equatable {
    /// The output would exceed the maximum side (16384 px).
    case tooLarge(width: Int, height: Int)
    /// The running OS can't write this format.
    case formatUnavailable(ExportFormat)
}

/// Labels for the primary export button.
public enum ExportLabel {
    /// `Export 2× • PNG`, `Export 4K • JPEG`, `Export 1290×2796 • PNG`.
    public static func title(format: ExportFormat, scale: ExportScale, nativeSize: PixelSize?) -> String {
        let size = nativeSize.map { "\($0.width)×\($0.height)" } ?? scale.displayName
        return "Export \(size) • \(format.displayName)"
    }

    /// VoiceOver reads the whole choice without symbols: `Export at 2 times as PNG, ⇧⌘E`.
    public static func spoken(format: ExportFormat, scale: ExportScale, nativeSize: PixelSize?) -> String {
        let size = nativeSize.map { "\($0.width) by \($0.height) pixels" } ?? scale.spokenName
        return "Export at \(size) as \(format.displayName), ⇧⌘E"
    }
}

/// Writes export files.
public enum FileExportError: Error, Equatable {
    case writeFailed(reason: String)
}

public enum FileExport {
    /// Writes atomically: either the complete file appears at `url` or nothing does.
    public static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw FileExportError.writeFailed(reason: error.localizedDescription)
        }
    }
}
