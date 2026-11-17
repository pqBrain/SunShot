import Foundation

/// Tolerant decoding: any missing key (a document from an older version) takes its default, so adding a field
/// never breaks opening existing documents. Encoding is synthesized from these keys.
extension Project {
    enum CodingKeys: String, CodingKey {
        case canvas, backdropSettings, padding, border, shadow, export, frame, tokens, annotationLayer, placement
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        canvas = try container.decodeIfPresent(CanvasSpec.self, forKey: .canvas) ?? canvas
        backdropSettings =
            try container.decodeIfPresent(BackdropSettings.self, forKey: .backdropSettings) ?? backdropSettings
        padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? padding
        border = try container.decodeIfPresent(Border.self, forKey: .border) ?? border
        shadow = try container.decodeIfPresent(Shadow.self, forKey: .shadow) ?? shadow
        export = try container.decodeIfPresent(ExportOptions.self, forKey: .export) ?? export
        frame = try container.decodeIfPresent(Frame.self, forKey: .frame) ?? frame
        tokens = try container.decodeIfPresent(DesignTokens.self, forKey: .tokens) ?? tokens
        annotationLayer = try container.decodeIfPresent(AnnotationLayer.self, forKey: .annotationLayer)
        placement = try container.decodeIfPresent(ContentPlacement.self, forKey: .placement) ?? placement
    }
}
