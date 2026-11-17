public import AppKit
public import Foundation
public import SunshotCore
import SunshotRender
public import UniformTypeIdentifiers

/// Export options (format, scale), the export button label, file names, export and copy.
extension EditorModel {
    public var exportOptions: ExportOptions { project.export }
    public var exportPlan: ExportPlan? { session.exportPlan }

    /// Formats offered in the options popover: those the running OS can write (WebP only if it can).
    public var availableFormats: [ExportFormat] { ImageCodec.writableFormats }

    public var exportButtonTitle: String {
        ExportLabel.title(
            format: exportOptions.format, scale: exportOptions.scale, nativeSize: project.canvas.nativeSize)
    }

    public var exportAccessibilityLabel: String {
        ExportLabel.spoken(
            format: exportOptions.format, scale: exportOptions.scale, nativeSize: project.canvas.nativeSize)
    }

    /// Store sizes always export at their own size: the scale picker is disabled for them.
    public var isScaleSelectable: Bool { project.canvas.nativeSize == nil }

    /// Read-only "Resolution" row: `2256 × 1456`.
    public var resolutionText: String {
        guard let plan = exportPlan else { return "—" }
        return UIStrings.pixelSize(width: plan.width, height: plan.height)
    }

    /// Read-only "Format" row: `.png`.
    public var formatText: String { ".\(exportOptions.format.fileExtension)" }

    /// Why export is blocked right now (too large), shown in the popover; nil when export is possible.
    public var exportProblem: String? {
        guard let plan = exportPlan, plan.isTooLarge else { return nil }
        return UIStrings.exportTooLarge
    }

    /// Informational note: JPEG flattens a see-through backdrop onto white.
    public var exportNotice: String? {
        guard exportOptions.format == .jpeg, !project.backdrop.isOpaque else { return nil }
        return UIStrings.jpegNoTransparency
    }

    public var canExport: Bool { hasContent && exportProblem == nil }

    public var exportContentType: UTType {
        UTType(exportOptions.format.typeIdentifier) ?? .png
    }

    /// File name for the save panel, from the default template (S7 makes it configurable).
    public func suggestedExportName(
        now: Date = Date(), template: String = SunshotDefaults.filenameTemplate,
        random: () -> String = { FilenameTemplate.randomToken() }
    ) -> String {
        let plan = exportPlan
        let context = FilenameContext(
            templateName: session.document.snippet == nil ? SunshotDefaults.templateName : CodeSnippet.templateName,
            scale: plan?.isNativeSize == true ? .x1 : exportOptions.scale, date: now, width: plan?.width ?? 0,
            height: plan?.height ?? 0, format: exportOptions.format)
        return FilenameTemplate.fileName(template: template, context: context, random: random)
    }

    /// The encoded file for the current options, rendered off the main actor.
    public func exportData() async throws -> Data {
        let session = self.session
        return try await Task.detached(priority: .userInitiated) { try session.exportImageData() }.value
    }

    /// The PNG that Copy puts on the pasteboard (export scale, always PNG).
    public func pngData() async throws -> Data {
        let session = self.session
        return try await Task.detached(priority: .userInitiated) { try session.copyPNGData() }.value
    }

    /// Copies exactly one PNG representation of the full canvas at the export scale.
    public func copyPNG(to pasteboard: NSPasteboard) async {
        do {
            PasteboardIO.writePNG(try await pngData(), to: pasteboard)
        } catch {
            alert = AlertContent(title: Self.exportFailedTitle, message: Self.describe(error))
        }
    }

    /// Writes the file atomically; on failure nothing is left at `url` and an alert is shown.
    public func export(to url: URL) async {
        do {
            try FileExport.write(try await exportData(), to: url)
        } catch {
            alert = AlertContent(title: Self.exportFailedTitle, message: Self.describe(error))
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case FileExportError.writeFailed(let reason): reason
        case ExportError.tooLarge: UIStrings.exportTooLarge
        case ExportError.formatUnavailable(let format): UIStrings.formatUnavailable(format)
        default: error.localizedDescription
        }
    }

    // MARK: Canvas size

    /// Typed custom size. Returns false (canvas kept, no undo entry) when either side is invalid.
    @discardableResult
    public func setCustomCanvas(width: String, height: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setCustomCanvas(width: width, height: height) }
        return accepted
    }

    /// Canvas size at 1× that `preset` would give the current content (for tile labels).
    public func canvasSize(for preset: CanvasPreset) -> PixelSize? {
        guard let contentSize = session.document.contentPixelSize else { return preset.exactSize }
        var project = self.project
        project.canvas = .preset(preset)
        return CanvasLayout.compute(contentSize: contentSize, project: project).canvasSize
    }
}
