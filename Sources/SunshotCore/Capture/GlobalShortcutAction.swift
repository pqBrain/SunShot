import Foundation

/// S17: the actions a global shortcut can run from anywhere. Each has its own keys and on/off switch in Settings.
public enum GlobalShortcutAction: String, CaseIterable, Hashable, Sendable {
    case captureArea, captureWindow, openStudio

    /// ⇧⌘S, ⇧⌘W and ⇧⌘0: the capture ones match File ▸ Capture Area… / Capture Window….
    public var defaultShortcut: GlobalShortcut {
        switch self {
        case .captureArea: .default
        case .captureWindow: GlobalShortcut(keyCode: 13, modifiers: [.shift, .command], keyLabel: "W")
        case .openStudio: GlobalShortcut(keyCode: 29, modifiers: [.shift, .command], keyLabel: "0")
        }
    }

    /// Whether the action captures (and so follows Settings ▸ After a shortcut capture).
    public var captures: Bool { self != .openStudio }
}

extension GlobalShortcut {
    /// The same keys, whatever label was recorded (labels depend on the keyboard layout).
    public func sameKeys(as other: GlobalShortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

/// S17: the per-action view of the global shortcuts kept in `AppSettings`.
extension AppSettings {
    public func shortcut(for action: GlobalShortcutAction) -> GlobalShortcut {
        switch action {
        case .captureArea: captureShortcut
        case .captureWindow: windowShortcut
        case .openStudio: studioShortcut
        }
    }

    public mutating func setShortcut(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) {
        switch action {
        case .captureArea: captureShortcut = shortcut
        case .captureWindow: windowShortcut = shortcut
        case .openStudio: studioShortcut = shortcut
        }
    }

    public func isShortcutEnabled(_ action: GlobalShortcutAction) -> Bool {
        switch action {
        case .captureArea: captureHotkeyEnabled
        case .captureWindow: windowHotkeyEnabled
        case .openStudio: studioHotkeyEnabled
        }
    }

    public mutating func setShortcutEnabled(_ enabled: Bool, for action: GlobalShortcutAction) {
        switch action {
        case .captureArea: captureHotkeyEnabled = enabled
        case .captureWindow: windowHotkeyEnabled = enabled
        case .openStudio: studioHotkeyEnabled = enabled
        }
    }

    /// The other action already using `shortcut`'s keys (on or off, so turning it back on never clashes), if any.
    public func shortcutConflict(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) -> GlobalShortcutAction?
    {
        GlobalShortcutAction.allCases.first { $0 != action && self.shortcut(for: $0).sameKeys(as: shortcut) }
    }

    /// The shortcuts to register: the enabled ones, each with keys no earlier action already took.
    public var activeShortcuts: [GlobalShortcutAction: GlobalShortcut] {
        var result: [GlobalShortcutAction: GlobalShortcut] = [:]
        for action in GlobalShortcutAction.allCases where isShortcutEnabled(action) {
            let keys = shortcut(for: action)
            guard keys.isValid, !result.values.contains(where: { $0.sameKeys(as: keys) }) else { continue }
            result[action] = keys
        }
        return result
    }

    /// Whether any capture shortcut is on (the "After a shortcut capture" choice then matters).
    public var hasCaptureShortcut: Bool {
        GlobalShortcutAction.allCases.contains { $0.captures && isShortcutEnabled($0) }
    }
}
