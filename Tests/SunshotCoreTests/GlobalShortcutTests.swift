import Foundation
import SunshotCore
import Testing

@Suite("Global capture shortcut")
struct GlobalShortcutTests {
    private func keys(_ code: UInt32, _ modifiers: GlobalShortcut.Modifiers, _ label: String = "K") -> GlobalShortcut {
        GlobalShortcut(keyCode: code, modifiers: modifiers, keyLabel: label)
    }

    @Test("[S10-AC19] [S16-AC1] the default is ⌥⇧⌘4, copying with the default style")
    func defaults() {
        #expect(GlobalShortcut.default.description == "⌥⇧⌘4")
        #expect(GlobalShortcut.default.isValid)
        #expect(AppSettings().captureShortcut == .default)
        #expect(AppSettings().globalCaptureDestination == .styledClipboard)
        #expect(GlobalCaptureDestination.styledClipboard.copies && !GlobalCaptureDestination.editor.copies)
    }

    @Test("[S10-AC19] new keys need a strong modifier and may not be macOS's screenshot keys")
    func validation() {
        #expect(keys(40, []).problem == .needsModifier)
        #expect(keys(40, [.shift]).problem == .needsModifier)
        #expect(keys(8, [.command]).problem == .needsModifier, "⌘C would break copy everywhere")
        #expect(keys(40, [.control, .shift]).isValid)
        #expect(keys(40, [.option, .command]).isValid)
        #expect(keys(40, [.shift, .command]).isValid)
        #expect(keys(120, [], "F2").isValid, "function keys work alone")
        for code: UInt32 in [20, 21, 23, 22] {
            #expect(keys(code, [.shift, .command]).problem == .reservedBySystem)
            #expect(keys(code, [.control, .shift, .command]).problem == .reservedBySystem)
        }
        #expect(keys(21, [.control, .option, .command]).isValid)
    }

    @Test("[S10-AC19] shortcuts display in macOS order with named keys")
    func labels() {
        #expect(keys(40, [.command, .shift, .option, .control], "K").description == "⌃⌥⇧⌘K")
        #expect(GlobalShortcut.label(keyCode: 40, characters: "k") == "K")
        #expect(GlobalShortcut.label(keyCode: 49, characters: " ") == "Space")
        #expect(GlobalShortcut.label(keyCode: 122, characters: "\u{F704}") == "F1")
        #expect(GlobalShortcut.label(keyCode: 126, characters: nil) == "↑")
        #expect(GlobalShortcut.label(keyCode: 200, characters: "") == "#200")
    }

    @Test("[S10-AC19] a shortcut round-trips through JSON")
    func coding() throws {
        let shortcut = keys(40, [.control, .option], "K")
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(GlobalShortcut.self, from: data) == shortcut)
    }
}
