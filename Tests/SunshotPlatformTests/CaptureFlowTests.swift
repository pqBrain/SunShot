import AppKit
import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

/// A screen that never exists: permission and results are scripted.
struct FakeScreen: ScreenCapturing {
    var granted = true
    var grantOnRequest = false
    var image: CGImage?
    var error: ScreenCaptureError?
    var windowList: [CapturableWindow] = []

    func hasPermission() -> Bool { granted }
    func requestPermission() -> Bool { grantOnRequest }
    func windows() async throws -> [CapturableWindow] {
        if let error { throw error }
        return windowList
    }
    func captureWindow(id: UInt32) async throws -> CGImage { try result() }
    func captureArea(_ rect: LayoutRect, displayID: UInt32) async throws -> CGImage { try result() }

    private func result() throws -> CGImage {
        if let error { throw error }
        guard let image else { throw ScreenCaptureError.failed("no image") }
        return image
    }
}

/// A web capturer that waits `delay`, then returns `image` (or throws `error`). Never touches the network.
struct FakeWeb: WebPageCapturing {
    var delay: Duration = .zero
    var image: CGImage?
    var error: WebCaptureError?

    @MainActor func capture(url: URL, options: WebCaptureOptions) async throws -> CGImage {
        try await Task.sleep(for: delay)
        if let error { throw error }
        guard let image else { throw WebCaptureError.snapshotFailed }
        return image
    }
}

@MainActor
@Suite("Capture flows", .serialized)
struct CaptureFlowTests {
    private func image(_ width: Int = 120, _ height: Int = 80) throws -> CGImage {
        try TestImages.solid(width: width, height: height)
    }

    private func model(screen: FakeScreen = FakeScreen(), web: FakeWeb = FakeWeb()) -> EditorModel {
        let model = EditorModel()
        model.capture.screen = screen
        model.capture.web = web
        return model
    }

    // MARK: Website

    @Test("[S10-AC13] an invalid address shows a reason and loads nothing")
    func invalidAddress() async throws {
        let model = model(web: FakeWeb(image: try image()))
        for text in ["", "file:///etc/hosts", "javascript:alert(1)"] {
            model.capture.websiteText = text
            await model.captureWebsite().value
            #expect(model.capture.websiteError != nil, "\(text)")
            #expect(!model.capture.isCapturingWebsite && !model.hasContent)
        }
        model.capture.websiteText = "   "
        #expect(!model.capture.canCaptureWebsite)
        model.capture.websiteText = "example.com"
        #expect(model.capture.canCaptureWebsite)
    }

    @Test("[S10-AC14] a website capture replaces the content as one step and keeps the PNG")
    func websiteSuccess() async throws {
        let model = model(web: FakeWeb(image: try image(390, 844)))
        model.capture.showsWebsiteSheet = true
        model.capture.websiteText = "example.com"
        let task = model.captureWebsite()
        #expect(model.capture.isCapturingWebsite && !model.capture.canCaptureWebsite)
        await task.value
        #expect(!model.capture.isCapturingWebsite && !model.capture.showsWebsiteSheet)
        #expect(model.capture.websiteError == nil)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 390, height: 844))
        let data = try #require(model.session.document.content?.data)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(model.undoTitle == "Undo Capture Website")
        await model.undo()
        #expect(!model.hasContent)
    }

    @Test("[S10-AC14] a page slower than the timeout fails with a message; the document is unchanged")
    func websiteTimeout() async throws {
        let model = model(web: FakeWeb(delay: .seconds(30), image: try image()))
        model.capture.websiteText = "example.com"
        model.capture.webOptions.timeoutSeconds = 1
        await model.captureWebsite().value
        #expect(model.capture.websiteError == WebCaptureError.timedOut.reason)
        #expect(!model.capture.isCapturingWebsite && !model.hasContent)
    }

    @Test("[S10-AC14] Cancel stops a capture silently; a cancelled capture finishing late changes nothing")
    func websiteCancel() async throws {
        let model = model(web: FakeWeb(delay: .seconds(30), image: try image()))
        model.capture.websiteText = "example.com"
        let task = model.captureWebsite()
        model.cancelWebsiteCapture()
        await task.value
        #expect(!model.capture.isCapturingWebsite && model.capture.websiteError == nil && !model.hasContent)

        // A slow capture that is superseded: only the newest one lands.
        model.capture.web = FakeWeb(delay: .milliseconds(300), image: try image(10, 10))
        let first = model.captureWebsite()
        model.capture.web = FakeWeb(image: try image(20, 20))
        let second = model.captureWebsite()
        await second.value
        await first.value
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 20, height: 20))
        #expect(model.session.history.undoCount == 1)
    }

    @Test("[S10-AC14] load failures show their reason")
    func websiteFailure() async throws {
        let model = model(web: FakeWeb(error: .loadFailed("offline")))
        model.capture.websiteText = "example.com"
        await model.captureWebsite().value
        #expect(model.capture.websiteError == WebCaptureError.loadFailed("offline").reason)
        model.capture.web = FakeWeb(error: .cancelled)
        await model.captureWebsite().value
        #expect(model.capture.websiteError == nil)
    }

    // MARK: Screen

    @Test("[S10-AC15] area and window captures replace the content as one step, keeping the style")
    func screenCaptures() async throws {
        let model = model(screen: FakeScreen(image: try image(300, 200)))
        await model.importData(try TestImages.png())
        model.perform { $0.setCornerStyle(.sharp) }
        await model.captureArea(LayoutRect(x: 10, y: 10, width: 150, height: 100), displayID: 1)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 300, height: 200))
        #expect(model.undoTitle == "Undo Capture Screenshot")
        #expect(model.project.border.style == .sharp)
        #expect(!model.capture.isCapturingScreen)

        model.capture.screen = FakeScreen(image: try image(64, 48))
        let depth = model.session.history.undoCount
        await model.captureArea(LayoutRect(x: 0, y: 0, width: 4, height: 40), displayID: 1)
        #expect(model.session.history.undoCount == depth, "areas under 8 pt are ignored")
        await model.captureWindow(id: 7)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 64, height: 48))
        #expect(!model.capture.showsWindowPicker)
    }

    @Test("[S10-AC15] the window picker lists capturable windows")
    func windowPicker() async throws {
        let windows = [
            CapturableWindow(id: 1, title: "Doc", appName: "Writer", width: 800, height: 600),
            CapturableWindow(id: 2, title: "", appName: "Tiny", width: 20, height: 20),
        ]
        let model = model(screen: FakeScreen(windowList: windows))
        await model.loadCapturableWindows()
        #expect(model.capture.showsWindowPicker)
        #expect(model.capture.windows.map(\.id) == [1])
    }

    @Test("[S10-AC16] without permission nothing is captured and the help is shown")
    func permissionDenied() async throws {
        let model = model(screen: FakeScreen(granted: false, image: try image()))
        #expect(!model.ensureScreenCapturePermission())
        #expect(model.capture.showsPermissionHelp)
        model.capture.showsPermissionHelp = false
        await model.captureArea(LayoutRect(x: 0, y: 0, width: 100, height: 100), displayID: 1)
        await model.loadCapturableWindows()
        #expect(model.capture.showsPermissionHelp && !model.capture.showsWindowPicker && !model.hasContent)
        #expect(model.alert == nil)

        // Granted when asked: the capture goes ahead.
        model.capture.screen = FakeScreen(granted: false, grantOnRequest: true, image: try image())
        await model.captureArea(LayoutRect(x: 0, y: 0, width: 100, height: 100), displayID: 1)
        #expect(model.hasContent)

        // Declined by ScreenCaptureKit itself (e.g. revoked while running).
        let revoked = self.model(screen: FakeScreen(error: .permissionDenied))
        await revoked.captureWindow(id: 1)
        #expect(revoked.capture.showsPermissionHelp && !revoked.hasContent && revoked.alert == nil)
    }

    @Test("[S10-AC16] other capture failures show a one-line alert")
    func otherFailures() async throws {
        let model = model(screen: FakeScreen(error: .failed("The display went to sleep.")))
        await model.captureArea(LayoutRect(x: 0, y: 0, width: 100, height: 100), displayID: 1)
        #expect(model.alert?.message == "The display went to sleep.")
        #expect(model.alert?.title == ScreenCaptureError.failed("").title)
        model.alert = nil
        model.capture.screen = FakeScreen(error: .windowNotFound)
        await model.loadCapturableWindows()
        #expect(model.alert?.message == ScreenCaptureError.windowNotFound.reason && !model.hasContent)
    }

    @Test("[S10-AC16] ScreenCaptureKit errors map to clear reasons")
    func errorMapping() {
        let declined = NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3801)
        #expect(SystemScreenCapturer.mapped(declined) == .permissionDenied)
        #expect(SystemScreenCapturer.mapped(ScreenCaptureError.noDisplay) == .noDisplay)
        let other = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        #expect(SystemScreenCapturer.mapped(other) == .failed("boom"))
    }

    // MARK: Menus and settings

    @Test("[S10-AC17] capture and crop menu items have unique shortcuts; the global shortcut setting persists")
    func menusAndSettings() {
        let expected: [(MenuCommand, String, String)] = [
            (.captureArea, "Capture Area…", "⌥⇧⌘4"), (.captureWindow, "Capture Window…", "⌥⇧⌘5"),
            (.captureWebsite, "Capture Website…", "⌥⇧⌘L"), (.crop, "Crop…", "⌥⌘C"),
        ]
        for (command, title, shortcut) in expected {
            #expect(MenuCatalog.title(command) == title)
            #expect(MenuCatalog.shortcut(command)?.description == shortcut)
        }
        #expect(
            MenuCatalog.menus.first { $0.title == "File" }?.items.contains { $0.command == .captureWebsite } == true)
        #expect(MenuCatalog.menus.first { $0.title == "Edit" }?.items.contains { $0.command == .crop } == true)
        #expect(MenuCatalog.clashes.isEmpty)

        let suite = "app.sunshot.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(!store.load().captureHotkeyEnabled)
        var settings = store.load()
        settings.captureHotkeyEnabled = true
        store.save(settings)
        #expect(store.load().captureHotkeyEnabled)
    }
}
