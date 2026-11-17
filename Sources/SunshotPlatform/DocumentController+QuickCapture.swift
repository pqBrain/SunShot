public import AppKit
public import Foundation
public import SunshotCore
import SunshotRender
import os

/// S16: the default style file. A missing or unreadable file means "no default style" (never fatal).
public struct QuickStyleStore: Sendable {
    public let file: URL
    private static let log = Logger(subsystem: "app.sunshot", category: "quick-style")

    public init(file: URL) {
        self.file = file
    }

    public func load() -> QuickStyle? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        do {
            return try QuickStyle.decode(data)
        } catch {
            Self.log.error("Ignoring unreadable default style \(self.file.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    public func save(_ style: QuickStyle) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try style.encoded().write(to: file, options: .atomic)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}

/// S16: the default style (quick captures and new documents) and where a capture goes.
extension DocumentController {
    public static let defaultStyleSavedNotice = "Saved as your default style"
    public static let defaultStyleFailedTitle = "Couldn't save the default style"

    /// The style quick captures are copied with: the saved default style, else the default template's.
    public var effectiveQuickStyle: QuickStyle { quickStyle ?? QuickStyle(project: defaultTemplateDocument.project) }

    public var hasQuickStyle: Bool { quickStyle != nil }

    /// Whether the open document's style and layout are exactly the saved default (the inspector's Set as Default
    /// button then shows as done).
    public var isCurrentStyleDefault: Bool {
        guard let quickStyle else { return false }
        return QuickStyle(project: model.project, savedAt: quickStyle.savedAt) == quickStyle
    }

    /// Saves the current style and layout as the default (Format ▸ Save as Default Style). Not an undoable document
    /// edit: it is a preference, like Settings.
    public func saveQuickStyle(now: Date = Date()) {
        let style = QuickStyle(project: model.project, savedAt: now)
        do {
            try QuickStyleStore(file: locations.quickStyle).save(style)
            quickStyle = style
            model.notice = Self.defaultStyleSavedNotice
        } catch {
            model.alert = AlertContent(title: Self.defaultStyleFailedTitle, message: error.localizedDescription)
        }
    }

    /// Forgets the default style; new documents use the default template again.
    public func clearQuickStyle() {
        try? QuickStyleStore(file: locations.quickStyle).delete()
        quickStyle = nil
    }

    /// Delivers a capture to `destination`. Returns whether something was copied (the caller shows the "copied"
    /// bubble); an editor capture opens in the studio, in Annotate mode when Settings asks for it.
    @discardableResult
    public func deliverCapture(
        _ source: CaptureSource, to destination: GlobalCaptureDestination, pasteboard: NSPasteboard = .general
    ) async -> Bool {
        switch destination {
        case .editor:
            await model.capture(source)
            if settings.annotateOnOpen { model.setAnnotateMode(true) }
            return false
        case .clipboard:
            return await model.copyCaptured(source, to: pasteboard, as: .raw)
        case .styledClipboard:
            return await model.copyCaptured(source, to: pasteboard, as: .styled(effectiveQuickStyle))
        }
    }
}
