public import Foundation
public import SunshotCore

/// Canvas size and export options. Each edit is one named undo step; edits that change nothing record nothing.
extension EditorSession {
    public static let canvasSizeActionName = "Change Canvas Size"
    public static let exportFormatActionName = "Change Export Format"
    public static let exportScaleActionName = "Change Export Scale"

    public mutating func setCanvas(_ canvas: CanvasSpec) {
        editProject(Self.canvasSizeActionName) { $0.canvas = canvas }
    }

    public mutating func selectCanvasPreset(_ preset: CanvasPreset) { setCanvas(.preset(preset)) }

    public mutating func resetCanvas() { setCanvas(.auto) }

    /// Typed custom size. Returns false (canvas kept, no undo entry) when a side isn't a whole number in
    /// 1…16384; an empty side means Auto for that side, both empty means Auto.
    @discardableResult
    public mutating func setCustomCanvas(width: String, height: String) -> Bool {
        guard let canvas = CanvasSideInput.canvas(width: width, height: height) else { return false }
        setCanvas(canvas)
        return true
    }

    public mutating func setExportFormat(_ format: ExportFormat) {
        editProject(Self.exportFormatActionName) { $0.export.format = format }
    }

    public mutating func setExportScale(_ scale: ExportScale) {
        editProject(Self.exportScaleActionName) { $0.export.scale = scale }
    }

    /// Output size for the current options, or nil when there's no content.
    public var exportPlan: ExportPlan? {
        guard let canvas = canvasSize else { return nil }
        let project = document.project
        return ExportPlan(canvas: canvas, scale: project.export.scale, isNativeSize: project.canvas.nativeSize != nil)
    }

    /// Renders and encodes with the document's export options (format and scale).
    /// Throws `ExportError.tooLarge` before rendering anything when a side would exceed 16384 px.
    public func exportImageData() throws -> Data {
        try exportData(format: document.project.export.format)
    }

    /// A PNG at the export scale (Copy always puts a PNG on the pasteboard, whatever the file format).
    public func copyPNGData() throws -> Data { try exportData(format: .png) }

    func exportData(format: ExportFormat) throws -> Data {
        guard let plan = exportPlan else { throw RenderError.noContent }
        guard !plan.isTooLarge else { throw ExportError.tooLarge(width: plan.width, height: plan.height) }
        guard ImageCodec.canWrite(format) else { throw ExportError.formatUnavailable(format) }
        guard let image = try render(scale: plan.renderScale) else { throw RenderError.noContent }
        return try ImageCodec.encode(image, as: format)
    }
}
