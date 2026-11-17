public import AppKit
import Foundation
public import SunshotCore
import SunshotRender
import os

/// S16: styles screenshots the macOS screenshot tool copies to the clipboard (⌃⌘⇧3/4, or ⌘⇧5 set to Clipboard).
/// macOS has no clipboard notification, so the change count is polled while the setting is on. Only a pasteboard
/// holding a single PNG marked as a macOS screenshot is touched: images copied from apps, files and Sunshot's own
/// copies are left alone. The screenshot is replaced with the default style's render, frame None (it already
/// shows its window's own title bar); the original stays beside it for the studio's paste.
@MainActor
public final class SystemScreenshotStyler {
    public static let pollInterval: Duration = .milliseconds(400)
    private static let log = Logger(subsystem: "app.sunshot", category: "clipboard-styler")

    private let pasteboard: NSPasteboard
    private let style: @MainActor () -> QuickStyle
    private var seenChangeCount: Int
    private var polling: Task<Void, Never>?
    /// Called after a screenshot was styled (the app shows the "copied" bubble).
    public var onStyled: (@MainActor () -> Void)?

    public init(pasteboard: NSPasteboard = .general, style: @escaping @MainActor () -> QuickStyle) {
        self.pasteboard = pasteboard
        self.style = style
        seenChangeCount = pasteboard.changeCount
    }

    public var isRunning: Bool { polling != nil }

    /// Starts or stops polling. Starting ignores whatever is on the clipboard already.
    public func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        if running {
            seenChangeCount = pasteboard.changeCount
            polling = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pollInterval)
                    await self?.check()
                }
            }
        } else {
            polling?.cancel()
            polling = nil
        }
    }

    /// Looks at the clipboard once: styles a new macOS screenshot in place. Returns whether it did.
    @discardableResult
    public func check() async -> Bool {
        let changeCount = pasteboard.changeCount
        guard changeCount != seenChangeCount else { return false }
        seenChangeCount = changeCount
        guard let data = Self.systemScreenshotData(on: pasteboard) else { return false }
        let quickStyle = style()
        do {
            let styled = try await Task.detached(priority: .userInitiated) {
                try QuickStyleRenderer.pngData(try ImageLoader.load(data), style: quickStyle, plainFrame: true)
            }.value
            // Something newer was copied while rendering: leave it.
            guard pasteboard.changeCount == changeCount else { return false }
            // The original (with its macOS screenshot mark) goes along, for pasting into the studio.
            PasteboardIO.writeStyled(styled, original: data, to: pasteboard)
            seenChangeCount = pasteboard.changeCount
            onStyled?()
            return true
        } catch {
            Self.log.error(
                "Couldn't style a screenshot on the clipboard: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The PNG of a macOS screenshot when it is the only thing on `pasteboard`, else nil.
    static func systemScreenshotData(on pasteboard: NSPasteboard) -> Data? {
        guard let items = pasteboard.pasteboardItems, items.count == 1, items[0].types == [.png],
            let data = items[0].data(forType: .png), ImageLoader.isSystemScreenshot(data)
        else { return nil }
        return data
    }
}
