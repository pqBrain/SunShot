import CoreGraphics
import Foundation
public import SunshotCore
import SunshotRender
import os

/// Screen and website capture (S10). A capture replaces the content as one undo step ("Capture Screenshot" /
/// "Capture Website"), keeps the style, and stores the captured PNG as the original media. Failures never touch
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
        session.setCapturedContent(image, data: data, actionName: actionName)
        await refreshPreview()
    }
}
