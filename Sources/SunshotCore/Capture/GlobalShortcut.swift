import Foundation

/// The system-wide Capture Area shortcut (S10): a virtual key code, which is layout-independent and what the
/// hot-key API registers, plus modifiers and the key's label as recorded.
public struct GlobalShortcut: Codable, Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Why a recorded combination can't be the global shortcut.
    public enum Problem: Equatable, Sendable {
        /// Plain keys, ⇧ or ⌘ alone would take over everyday typing and editing in every app.
        case needsModifier
        /// macOS's own screenshot shortcuts (⇧⌘3, ⇧⌘4, ⇧⌘5, ⇧⌘6 and their ⌃ variants).
        case reservedBySystem
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// ⇧⌘S, the same keys as File ▸ Capture Area….
    public static let `default` = GlobalShortcut(keyCode: 1, modifiers: [.shift, .command], keyLabel: "S")

    /// `⇧⌘S` (modifiers in the standard macOS order).
    public var description: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    public var problem: Problem? {
        if Self.systemScreenshotKeys.contains(keyCode),
            modifiers == [.shift, .command] || modifiers == [.control, .shift, .command]
        {
            return .reservedBySystem
        }
        if Self.functionKeys[keyCode] != nil { return nil }
        let strong: Modifiers = [.control, .option, .command]
        let usable = !modifiers.isDisjoint(with: [.control, .option]) || modifiers.isSuperset(of: [.command, .shift])
        return modifiers.isDisjoint(with: strong) || !usable ? .needsModifier : nil
    }

    public var isValid: Bool { problem == nil }

    /// The label shown for `keyCode`: named keys by name, everything else from the typed characters.
    public static func label(keyCode: UInt32, characters: String?) -> String {
        if let name = functionKeys[keyCode] ?? namedKeys[keyCode] { return name }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return typed.isEmpty ? "#\(keyCode)" : typed
    }

    /// Key codes of 3, 4, 5 and 6.
    static let systemScreenshotKeys: Set<UInt32> = [20, 21, 23, 22]

    static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        90: "F20",
    ]

    static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}

/// Where a global-shortcut capture goes (Settings ▸ After a shortcut capture).
public enum GlobalCaptureDestination: String, Codable, CaseIterable, Sendable {
    /// Bring Sunshot forward with the capture in the editor (the original behaviour).
    case editor
    /// Copy the captured image to the clipboard, ready to paste; Sunshot stays in the background.
    case clipboard
    /// S16 (the default): copy the capture with the default style applied, ready to paste; Sunshot stays in the
    /// background.
    case styledClipboard

    /// Whether the capture goes to the clipboard (raw or styled) instead of the editor.
    public var copies: Bool { self != .editor }
}
