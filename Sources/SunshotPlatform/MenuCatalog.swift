/// Every menu-bar command. The app builds its menus from `MenuCatalog`, so titles and key equivalents are
/// defined (and unit-tested for clashes) in one place.
public enum MenuCommand: String, CaseIterable, Sendable {
    case settings, hide, hideOthers, quit
    case new, newCodeSnippet, open, importMultiple, openRecent, close, save, saveAs, exportImage, exportAll, startOver
    case templateGallery
    case undo, redo, cut, copy, paste, selectAll, clearContent
    case toggleInspector, enterFullScreen
    case minimize, zoom
    case help
}

/// A key equivalent such as ⇧⌘E.
public struct KeyShortcut: Hashable, Sendable, CustomStringConvertible {
    public enum Modifier: String, Hashable, Sendable, CaseIterable {
        case control, option, shift, command
        var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    /// A single lower-case character, or `delete` for ⌫.
    public let key: String
    public let modifiers: Set<Modifier>

    public init(_ key: String, _ modifiers: Set<Modifier> = [.command]) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let deleteKey = "delete"

    /// `⇧⌘E` (modifiers in the standard macOS order).
    public var description: String {
        let symbols = Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined()
        return symbols + (key == Self.deleteKey ? "⌫" : key.uppercased())
    }
}

public struct MenuItemSpec: Sendable {
    public let command: MenuCommand
    public let title: String
    public let shortcut: KeyShortcut?
    /// Provided by macOS / SwiftUI (listed so the clash check covers them); the app doesn't build these.
    public let isSystem: Bool

    init(_ command: MenuCommand, _ title: String, _ shortcut: KeyShortcut? = nil, system: Bool = false) {
        self.command = command
        self.title = title
        self.shortcut = shortcut
        self.isSystem = system
    }
}

public struct MenuSpec: Sendable {
    public let title: String
    public let items: [MenuItemSpec]
}

public enum MenuCatalog {
    public static let menus: [MenuSpec] = [
        MenuSpec(
            title: "Sunshot",
            items: [
                MenuItemSpec(.settings, "Settings…", KeyShortcut(","), system: true),
                MenuItemSpec(.hide, "Hide Sunshot", KeyShortcut("h"), system: true),
                MenuItemSpec(.hideOthers, "Hide Others", KeyShortcut("h", [.command, .option]), system: true),
                MenuItemSpec(.quit, "Quit Sunshot", KeyShortcut("q"), system: true),
            ]),
        MenuSpec(
            title: "File",
            items: [
                MenuItemSpec(.new, "New", KeyShortcut("n")),
                MenuItemSpec(.newCodeSnippet, "New Code Snippet", KeyShortcut("n", [.command, .option])),
                MenuItemSpec(.templateGallery, "Templates…", KeyShortcut("t", [.command, .shift])),
                MenuItemSpec(.open, "Open…", KeyShortcut("o")),
                MenuItemSpec(.importMultiple, "Import Multiple…", KeyShortcut("o", [.command, .shift])),
                MenuItemSpec(.openRecent, "Open Recent"),
                MenuItemSpec(.close, "Close", KeyShortcut("w")),
                MenuItemSpec(.save, "Save", KeyShortcut("s")),
                MenuItemSpec(.saveAs, "Save As…", KeyShortcut("s", [.command, .shift])),
                MenuItemSpec(.exportImage, "Export Image…", KeyShortcut("e", [.command, .shift])),
                MenuItemSpec(.exportAll, "Export All…", KeyShortcut("e", [.command, .option, .shift])),
                MenuItemSpec(.startOver, "Start Over"),
            ]),
        MenuSpec(
            title: "Edit",
            items: [
                MenuItemSpec(.undo, "Undo", KeyShortcut("z")),
                MenuItemSpec(.redo, "Redo", KeyShortcut("z", [.command, .shift])),
                MenuItemSpec(.cut, "Cut", KeyShortcut("x")),
                MenuItemSpec(.copy, "Copy", KeyShortcut("c")),
                MenuItemSpec(.paste, "Paste", KeyShortcut("v")),
                MenuItemSpec(.selectAll, "Select All", KeyShortcut("a")),
                MenuItemSpec(.clearContent, "Clear Content", KeyShortcut(KeyShortcut.deleteKey)),
            ]),
        MenuSpec(
            title: "View",
            items: [
                MenuItemSpec(.toggleInspector, "Show/Hide Inspector", KeyShortcut("e", [.command, .option])),
                MenuItemSpec(
                    .enterFullScreen, "Enter Full Screen", KeyShortcut("f", [.command, .control]), system: true),
            ]),
        MenuSpec(
            title: "Window",
            items: [
                MenuItemSpec(.minimize, "Minimize", KeyShortcut("m"), system: true),
                MenuItemSpec(.zoom, "Zoom", system: true),
            ]),
        MenuSpec(title: "Help", items: [MenuItemSpec(.help, "Sunshot Help", KeyShortcut("?"), system: true)]),
    ]

    public static var items: [MenuItemSpec] { menus.flatMap(\.items) }

    public static func item(_ command: MenuCommand) -> MenuItemSpec? {
        items.first { $0.command == command }
    }

    public static func shortcut(_ command: MenuCommand) -> KeyShortcut? { item(command)?.shortcut }

    public static func title(_ command: MenuCommand) -> String { item(command)?.title ?? command.rawValue }

    /// Key equivalents used by more than one item (must be empty).
    public static var clashes: [KeyShortcut] {
        var seen: Set<KeyShortcut> = []
        var clashes: [KeyShortcut] = []
        for shortcut in items.compactMap(\.shortcut) where !seen.insert(shortcut).inserted {
            clashes.append(shortcut)
        }
        return clashes
    }
}
