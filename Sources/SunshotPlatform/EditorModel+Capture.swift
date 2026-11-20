public import AppKit
import CoreGraphics
import Foundation
public import SunshotCore
import SunshotRender
import os

/// S16: what a capture is of.
public enum CaptureSource: Equatable, Sendable {
    /// Display points, top-left origin, of display `displayID`.
    case area(LayoutRect, displayID: UInt32)
    case window(UInt32)
}

/// S16: how a capture is copied: as captured, or with a style (the default style) applied.
public enum CaptureCopyStyle: Equatable, Sendable {
    case raw
    case styled(QuickStyle?)
}

/// Screen and website capture (S10). The first capture becomes the content as one undo step ("Capture Screenshot" /
/// "Capture Website"); with image content already open it is added as the next screenshot (S15). Keeps the style, and stores the captured PNG as the original media. Failures never touch
/// the document: they show a message (permission problems offer System Settings).
extension EditorModel {
    private static let captureLogger = Logger(subsystem: "app.sunshot", category: "capture")

    // MARK: Screen

    /// Checks Screen Recording permission before an area or window capture, asking macOS once if needed.
    /// Returns false (and shows the permission help) when it is not granted.
    @discardableResult
    public func ensureScreenCapturePermission() -> Bool {
        if capture.screen.hasPermission() || capture.screen.requestPermission() { return true }
        capture.showsPermissionHelp = true
        return false
    }

    /// Fills the window picker. Sunshot's own windows are left out.
    public func loadCapturableWindows() async {
        guard ensureScreenCapturePermission() else { return }
        do {
            let all = try await capture.screen.windows()
            capture.windows = CapturableWindow.pickable(all, excludingApp: ownAppName)
            capture.showsWindowPicker = true
        } catch {
            report(error)
        }
    }

    public func captureWindow(id: UInt32) async {
        capture.showsWindowPicker = false
        let screen = capture.screen
        await runScreenCapture { try await screen.captureWindow(id: id) }
    }

    /// Captures `rect` (display points, top-left origin) of display `displayID`. Too-small areas do nothing.
    public func captureArea(_ rect: LayoutRect, displayID: UInt32) async {
        guard AreaSelection.isCapturable(rect) else { return }
        let screen = capture.screen
        await runScreenCapture { try await screen.captureArea(rect, displayID: displayID) }
    }

    /// A global-shortcut capture with the clipboard destination: the captured area is written to `pasteboard` as
    /// a PNG, ready to paste, and the document is unchanged. Returns whether it was copied; failures are reported
    /// as for any capture. S16: `.styled` copies it with the default style applied.
    @discardableResult
    public func copyCapturedArea(
        _ rect: LayoutRect, displayID: UInt32, to pasteboard: NSPasteboard, as style: CaptureCopyStyle = .raw
    ) async -> Bool {
        guard AreaSelection.isCapturable(rect) else { return false }
        return await copyCaptured(.area(rect, displayID: displayID), to: pasteboard, as: style)
    }

    /// S16: captures `source` and writes it to `pasteboard` (raw or styled); the document is unchanged.
    @discardableResult
    public func copyCaptured(
        _ source: CaptureSource, to pasteboard: NSPasteboard, as style: CaptureCopyStyle
    ) async
        -> Bool
    {
        guard ensureScreenCapturePermission() else { return false }
        capture.isCapturingScreen = true
        defer { capture.isCapturingScreen = false }
        do {
            return try await copyImage(try await capturedImage(source), to: pasteboard, as: style)
        } catch {
            report(error)
            return false
        }
    }

    /// Writes an already captured `image` to `pasteboard` (raw or styled); the document is unchanged.
    @discardableResult
    func copyImage(_ image: CGImage, to pasteboard: NSPasteboard, as style: CaptureCopyStyle) async throws -> Bool {
        let (data, original) = try await Task.detached(priority: .userInitiated) {
            let original = try ImageCodec.pngData(image)
            switch style {
            case .raw: return (original, Data?.none)
            case .styled(let quickStyle):
                do {
                    return (try QuickStyleRenderer.pngData(image, style: quickStyle), original)
                } catch ExportError.tooLarge {
                    // Too big to style (over the maximum side): copy the capture itself rather than nothing.
                    return (original, Data?.none)
                }
            }
        }.value
        if let original {
            PasteboardIO.writeStyled(data, original: original, to: pasteboard)
        } else {
            PasteboardIO.writePNG(data, to: pasteboard)
        }
        return true
    }

    /// Freeze capture: grabs the whole display now (Sunshot's own windows left out); nil when it can't (the
    /// permission help or an alert is shown).
    public func freezeDisplay(size: (width: Double, height: Double), displayID: UInt32) async -> CGImage? {
        guard ensureScreenCapturePermission() else { return nil }
        do {
            return try await capture.screen.captureArea(
                LayoutRect(x: 0, y: 0, width: size.width, height: size.height), displayID: displayID)
        } catch {
            report(error)
            return nil
        }
    }

    /// Freeze capture: the finished image goes into the document, or to the clipboard (raw or styled).
    @discardableResult
    public func deliverFrozen(
        _ image: CGImage, to pasteboard: NSPasteboard? = nil, as style: CaptureCopyStyle? = nil
    ) async -> Bool {
        guard let pasteboard, let style else {
            await setCaptured(image, actionName: EditorSession.captureScreenActionName)
            return false
        }
        do {
            return try await copyImage(image, to: pasteboard, as: style)
        } catch {
            report(error)
            return false
        }
    }

    /// S16: captures `source` into the document (as File ▸ Capture Area / Window do).
    public func capture(_ source: CaptureSource) async {
        switch source {
        case .area(let rect, let displayID): await captureArea(rect, displayID: displayID)
        case .window(let id): await captureWindow(id: id)
        }
    }

    /// S16: the windows the hover picker offers, front to back, or nil (permission help shown) when not allowed.
    public func pickableWindows() async -> [CapturableWindow]? {
        guard ensureScreenCapturePermission() else { return nil }
        do {
            return WindowPicking.candidates(try await capture.screen.windows(), excludingApp: ownAppName)
        } catch {
            report(error)
            return nil
        }
    }

    private func capturedImage(_ source: CaptureSource) async throws -> CGImage {
        switch source {
        case .area(let rect, let displayID): try await capture.screen.captureArea(rect, displayID: displayID)
        case .window(let id): try await capture.screen.captureWindow(id: id)
        }
    }

    private func runScreenCapture(_ operation: @escaping @Sendable () async throws -> CGImage) async {
        guard ensureScreenCapturePermission() else { return }
        capture.isCapturingScreen = true
        defer { capture.isCapturingScreen = false }
        do {
            let image = try await operation()
            await setCaptured(image, actionName: EditorSession.captureScreenActionName)
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        let captureError = error as? ScreenCaptureError ?? .failed(error.localizedDescription)
        Self.captureLogger.error("screen capture failed: \(captureError.reason, privacy: .public)")
        if captureError == .permissionDenied {
            capture.showsPermissionHelp = true
        } else {
            alert = AlertContent(title: captureError.title, message: captureError.reason)
        }
    }

    private var ownAppName: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    // MARK: Website

    /// Validates the typed address and captures it. Invalid addresses show an inline error without loading
    /// anything. Await the returned task to wait for the result.
    @discardableResult
    public func captureWebsite() -> Task<Void, Never> {
        cancelWebsiteCapture()
        capture.websiteError = nil
        let url: URL
        do {
            url = try WebCaptureURL.parse(capture.websiteText)
        } catch {
            capture.websiteError = error.reason
            return Task {}
        }
        let options = capture.webOptions
        let web = capture.web
        capture.isCapturingWebsite = true
        capture.websiteGeneration += 1
        let generation = capture.websiteGeneration
        let task = Task { [weak self] in
            do {
                let image = try await withTimeout(seconds: options.clampedTimeout) {
                    try await web.capture(url: url, options: options)
                }
                try Task.checkCancellation()
                await self?.finishWebsiteCapture(image, generation: generation)
            } catch {
                self?.failWebsiteCapture(error, generation: generation)
            }
        }
        capture.websiteTask = task
        return task
    }

    /// Stops a running website capture; the document is unchanged.
    public func cancelWebsiteCapture() {
        capture.websiteGeneration += 1
        capture.websiteTask?.cancel()
        capture.websiteTask = nil
        capture.isCapturingWebsite = false
    }

    private func finishWebsiteCapture(_ image: CGImage, generation: Int) async {
        guard generation == capture.websiteGeneration else { return }
        capture.isCapturingWebsite = false
        capture.websiteTask = nil
        capture.showsWebsiteSheet = false
        await setCaptured(image, actionName: EditorSession.captureWebsiteActionName)
    }

    private func failWebsiteCapture(_ error: any Error, generation: Int) {
        guard generation == capture.websiteGeneration else { return }
        capture.isCapturingWebsite = false
        capture.websiteTask = nil
        if error is CancellationError || error as? WebCaptureError == .cancelled { return }
        let reason = (error as? WebCaptureError)?.reason ?? error.localizedDescription
        Self.captureLogger.error("website capture failed: \(reason, privacy: .public)")
        capture.websiteError = reason
    }

    // MARK: Content

    /// Sets a captured image as the content (encoded to PNG off the main actor for the saved original).
    func setCaptured(_ image: CGImage, actionName: String) async {
        let data = try? await Task.detached(priority: .userInitiated) { try ImageCodec.pngData(image) }.value
        // S15: a capture over an image adds the next screenshot instead of replacing it.
        // A web page's own margins are content, so website captures are never trimmed.
        await addScreenshot(
            image, data: data, replacingName: actionName,
            trims: actionName != EditorSession.captureWebsiteActionName)
        await refreshPreview()
    }
}
