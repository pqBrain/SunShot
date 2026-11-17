public import AppKit
public import CoreGraphics
public import Foundation
import ScreenCaptureKit
public import SunshotCore

/// Screen capture (S10) behind a protocol, so capture flows are testable without a screen or a permission prompt.
public protocol ScreenCapturing: Sendable {
    /// Whether Screen Recording is allowed (never prompts).
    func hasPermission() -> Bool
    /// Asks macOS for Screen Recording permission (shows the system prompt the first time); returns the result.
    func requestPermission() -> Bool
    /// Windows that can be captured, front to back.
    func windows() async throws -> [CapturableWindow]
    func captureWindow(id: UInt32) async throws -> CGImage
    /// `rect` in the display's points, top-left origin.
    func captureArea(_ rect: LayoutRect, displayID: UInt32) async throws -> CGImage
}

/// ScreenCaptureKit implementation. Sunshot's own windows are left out of area captures and the window list.
public struct SystemScreenCapturer: ScreenCapturing {
    public init() {}

    public func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    public func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public func windows() async throws -> [CapturableWindow] {
        let content = try await shareableContent()
        return content.windows.filter { $0.windowLayer == 0 && $0.isOnScreen }.map { window in
            CapturableWindow(
                id: window.windowID, title: window.title ?? "",
                appName: window.owningApplication?.applicationName ?? "", width: Int(window.frame.width),
                height: Int(window.frame.height))
        }
    }

    public func captureWindow(id: UInt32) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw ScreenCaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        configuration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        configuration.showsCursor = false
        // Sunshot draws its own shadow; the system window shadow would double it.
        configuration.ignoreShadowsSingleWindow = true
        return try await screenshot(filter, configuration)
    }

    public func captureArea(_ rect: LayoutRect, displayID: UInt32) async throws -> CGImage {
        guard AreaSelection.isCapturable(rect) else { throw ScreenCaptureError.selectionTooSmall }
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
        else { throw ScreenCaptureError.noDisplay }
        let ownBundle = Bundle.main.bundleIdentifier
        let own = content.applications.filter { $0.bundleIdentifier == ownBundle }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        let size = AreaSelection.pixelSize(of: rect, scale: Double(filter.pointPixelScale))
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        return try await screenshot(filter, configuration)
    }

    private func screenshot(_ filter: SCContentFilter, _ configuration: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw Self.mapped(error)
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        guard hasPermission() else { throw ScreenCaptureError.permissionDenied }
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Self.mapped(error)
        }
    }

    static func mapped(_ error: any Error) -> ScreenCaptureError {
        if let captureError = error as? ScreenCaptureError { return captureError }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .failed(nsError.localizedDescription)
    }
}

/// Display helpers for the area-selection overlay.
@MainActor
public enum ScreenDisplays {
    /// The Core Graphics display id of `screen` (what ScreenCaptureKit calls `displayID`).
    public static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The screen under the mouse pointer (where an area capture starts), else the main screen.
    public static var screenUnderPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    /// System Settings ▸ Privacy & Security ▸ Screen Recording.
    public static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}
