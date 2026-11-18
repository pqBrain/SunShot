import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Global capture shortcut settings and clipboard", .serialized)
struct GlobalCaptureTests {
    private func store() -> (SettingsStore, () -> Void) {
        let suite = "app.sunshot.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return (SettingsStore(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    @Test("[S10-AC19] changed keys and the after-capture choice are saved in Settings")
    func persistence() {
        let (store, cleanUp) = store()
        defer { cleanUp() }
        #expect(store.load().captureShortcut == .default)
        #expect(store.load().globalCaptureDestination == .styledClipboard)
        var settings = store.load()
        settings.captureShortcut = GlobalShortcut(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        settings.globalCaptureDestination = .clipboard
        store.save(settings)
        #expect(store.load().captureShortcut.description == "⌃⌥K")
        #expect(store.load().globalCaptureDestination == .clipboard)
    }

    @Test("[S10-AC19] stored keys that are no longer allowed fall back to the default")
    func invalidStoredShortcut() throws {
        let suite = "app.sunshot.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = GlobalShortcut(keyCode: 21, modifiers: [.shift, .command], keyLabel: "4")
        defaults.set(try JSONEncoder().encode(bad), forKey: SettingsStore.prefix + "captureShortcut")
        defaults.set("nowhere", forKey: SettingsStore.prefix + "captureDestination")
        let settings = SettingsStore(defaults: defaults).load()
        #expect(settings.captureShortcut == .default)
        #expect(settings.globalCaptureDestination == .styledClipboard)
    }

    @Test("[S17-AC6] Capture Window and Open Studio keys and switches survive relaunch")
    func perActionPersistence() {
        let (store, cleanUp) = store()
        defer { cleanUp() }
        var settings = store.load()
        #expect(settings.windowShortcut.description == "⇧⌘W" && settings.studioShortcut.description == "⇧⌘0")
        #expect(settings.windowHotkeyEnabled && settings.studioHotkeyEnabled)
        settings.setShortcut(
            GlobalShortcut(keyCode: 40, modifiers: [.control, .option], keyLabel: "K"), for: .openStudio)
        settings.setShortcutEnabled(false, for: .captureWindow)
        store.save(settings)
        let loaded = store.load()
        #expect(loaded.studioShortcut.description == "⌃⌥K")
        #expect(!loaded.windowHotkeyEnabled && loaded.studioHotkeyEnabled && loaded.captureHotkeyEnabled)
        #expect(loaded == settings)
    }

    @Test("[S17-AC6] a Capture Area shortcut saved before S17 carries over; invalid new keys fall back")
    func migration() throws {
        let suite = "app.sunshot.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mine = GlobalShortcut(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        defaults.set(try JSONEncoder().encode(mine), forKey: SettingsStore.prefix + "captureShortcut")
        defaults.set(false, forKey: SettingsStore.prefix + "captureHotkey")
        let bad = GlobalShortcut(keyCode: 23, modifiers: [.shift, .command], keyLabel: "5")
        defaults.set(try JSONEncoder().encode(bad), forKey: SettingsStore.prefix + "windowShortcut")
        let settings = SettingsStore(defaults: defaults).load()
        #expect(settings.captureShortcut == mine && !settings.captureHotkeyEnabled)
        #expect(settings.windowShortcut == GlobalShortcutAction.captureWindow.defaultShortcut)
        #expect(settings.studioShortcut == GlobalShortcutAction.openStudio.defaultShortcut)
        #expect(settings.windowHotkeyEnabled && settings.studioHotkeyEnabled)
    }

    @Test("[S10-AC20] copy-to-clipboard puts the captured PNG on the pasteboard and leaves the document alone")
    func copyToClipboard() async throws {
        let model = EditorModel()
        model.capture.screen = FakeScreen(image: try TestImages.solid(width: 300, height: 200))
        try await withPrivatePasteboard { pasteboard in
            let copied = await model.copyCapturedArea(
                LayoutRect(x: 0, y: 0, width: 150, height: 100), displayID: 1, to: pasteboard)
            #expect(copied)
            let data = try #require(pasteboard.data(forType: .png))
            let image = try ImageCodec.decode(data)
            #expect(image.width == 300 && image.height == 200)
            #expect(!model.hasContent && model.session.history.undoCount == 0)
            #expect(!model.capture.isCapturingScreen)

            // Too small, denied or failed: nothing copied, the clipboard keeps what it had.
            #expect(
                !(await model.copyCapturedArea(
                    LayoutRect(x: 0, y: 0, width: 4, height: 40), displayID: 1, to: pasteboard)))
            model.capture.screen = FakeScreen(granted: false)
            #expect(
                !(await model.copyCapturedArea(
                    LayoutRect(x: 0, y: 0, width: 100, height: 100), displayID: 1, to: pasteboard)))
            #expect(model.capture.showsPermissionHelp)
            model.capture.screen = FakeScreen(error: .failed("The display went to sleep."))
            #expect(
                !(await model.copyCapturedArea(
                    LayoutRect(x: 0, y: 0, width: 100, height: 100), displayID: 1, to: pasteboard)))
            #expect(model.alert?.message == "The display went to sleep.")
            #expect(pasteboard.data(forType: .png) == data)
        }
    }
}
