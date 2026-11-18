import Foundation
import SunshotCore
import Testing

@Suite("Global shortcuts per action")
struct GlobalShortcutActionTests {
    private func keys(_ code: UInt32, _ modifiers: GlobalShortcut.Modifiers, _ label: String = "K") -> GlobalShortcut {
        GlobalShortcut(keyCode: code, modifiers: modifiers, keyLabel: label)
    }

    @Test("[S17-AC6] Capture Area ⇧⌘S, Capture Window ⇧⌘W and Open Studio ⇧⌘0 are on by default")
    func defaults() {
        let settings = AppSettings()
        #expect(
            GlobalShortcutAction.allCases.map { settings.shortcut(for: $0).description } == ["⇧⌘S", "⇧⌘W", "⇧⌘0"])
        for action in GlobalShortcutAction.allCases {
            #expect(settings.isShortcutEnabled(action))
            #expect(action.defaultShortcut.isValid)
            #expect(settings.shortcut(for: action) == action.defaultShortcut)
        }
        #expect(settings.activeShortcuts.count == 3)
        #expect(settings.hasCaptureShortcut)
        #expect(GlobalShortcutAction.captureWindow.captures && !GlobalShortcutAction.openStudio.captures)
    }

    @Test("[S17-AC6] each shortcut is set and turned on or off on its own")
    func setAndToggle() {
        var settings = AppSettings()
        let custom = keys(40, [.control, .option])
        settings.setShortcut(custom, for: .openStudio)
        settings.setShortcutEnabled(false, for: .captureWindow)
        #expect(settings.studioShortcut == custom)
        #expect(settings.shortcut(for: .captureArea) == .default)
        #expect(!settings.windowHotkeyEnabled && settings.captureHotkeyEnabled && settings.studioHotkeyEnabled)
        #expect(settings.activeShortcuts == [.captureArea: .default, .openStudio: custom])
        settings.setShortcut(keys(41, [.control, .option]), for: .captureArea)
        settings.setShortcut(keys(42, [.control, .option]), for: .captureWindow)
        #expect(settings.captureShortcut.keyCode == 41 && settings.windowShortcut.keyCode == 42)
        settings.setShortcutEnabled(false, for: .captureArea)
        settings.setShortcutEnabled(false, for: .openStudio)
        #expect(!settings.hasCaptureShortcut)
        #expect(settings.activeShortcuts.isEmpty)
        settings.setShortcutEnabled(true, for: .captureWindow)
        settings.setShortcutEnabled(true, for: .openStudio)
        #expect(settings.hasCaptureShortcut && settings.studioHotkeyEnabled)
    }

    @Test("[S17-AC6] keys already used by another of the three are refused, even when that one is off")
    func conflicts() {
        var settings = AppSettings()
        let areaKeysOtherLabel = keys(1, [.shift, .command], "Ś")
        #expect(settings.shortcutConflict(areaKeysOtherLabel, for: .openStudio) == .captureArea)
        #expect(settings.shortcutConflict(.default, for: .captureArea) == nil)
        #expect(settings.shortcutConflict(keys(40, [.control, .option]), for: .captureWindow) == nil)
        settings.setShortcutEnabled(false, for: .captureWindow)
        #expect(
            settings.shortcutConflict(GlobalShortcutAction.captureWindow.defaultShortcut, for: .openStudio)
                == .captureWindow)
        // Keys clashing anyway (e.g. stored by an older build) register once, for the first action.
        settings.setShortcutEnabled(true, for: .captureWindow)
        settings.setShortcut(.default, for: .captureWindow)
        #expect(settings.activeShortcuts[.captureArea] == .default)
        #expect(settings.activeShortcuts[.captureWindow] == nil)
        #expect(settings.activeShortcuts[.openStudio] != nil)
    }
}
