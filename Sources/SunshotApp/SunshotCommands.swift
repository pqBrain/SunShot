import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// Menu bar, built from `MenuCatalog` (titles and key equivalents) and validated by `DocumentController`.
/// System items (app menu, full screen, Window, Help) come from SwiftUI/AppKit.
struct SunshotCommands: Commands {
    let controller: DocumentController

    private var model: EditorModel { controller.model }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item(.new) { Task { await DocumentFlows.newDocument(controller) } }
            item(.newCodeSnippet) { model.newCodeSnippet() }
            item(.open) { Task { await DocumentFlows.open(controller) } }
            Menu(MenuCatalog.title(.openRecent)) {
                ForEach(controller.recents.items) { recent in
                    Button(recent.name) { Task { await DocumentFlows.openRecent(recent, in: controller) } }
                }
                Divider()
                Button(UIStrings.clearMenu) { controller.clearRecents() }
                    .disabled(controller.recents.items.isEmpty)
            }
        }
        CommandGroup(replacing: .saveItem) {
            item(.close) { Task { await closeWindow() } }
            item(.save) { Task { await DocumentFlows.save(controller) } }
            item(.saveAs) { Task { await DocumentFlows.saveAs(controller) } }
        }
        CommandGroup(replacing: .importExport) {
            item(.exportImage) { Task { await DocumentFlows.export(controller) } }
            Divider()
            item(.startOver) { DocumentFlows.startOver(controller) }
        }
        CommandGroup(after: .sidebar) {
            item(.toggleInspector) { model.showsInspector.toggle() }
        }
        CommandGroup(replacing: .undoRedo) {
            item(.undo) { Task { await model.undo() } }
            item(.redo) { Task { await model.redo() } }
        }
        CommandGroup(replacing: .pasteboard) {
            item(.cut) { sendToTextField(#selector(NSText.cut(_:))) }
            item(.copy, enabled: controller.isEnabled(.copy) || isEditingText) {
                if !sendToTextField(#selector(NSText.copy(_:))) { Task { await model.copyPNG(to: .general) } }
            }
            item(.paste) {
                if !sendToTextField(#selector(NSText.paste(_:))) { Task { await model.paste(from: .general) } }
            }
            item(.selectAll) { sendToTextField(#selector(NSText.selectAll(_:))) }
            Divider()
            item(.clearContent) { Task { await model.clearContent() } }
        }
    }

    /// A catalog item: title, shortcut and enabled state all come from the platform layer.
    private func item(_ command: MenuCommand, enabled: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(controller.menuTitle(command), action: action)
            .keyboardShortcut(MenuCatalog.shortcut(command).map(Self.keyboardShortcut))
            .disabled(!(enabled ?? controller.isEnabled(command)))
    }

    private var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSText }

    /// Standard edit actions go to a focused text field (Settings, theme name); returns false when there is none.
    @discardableResult
    private func sendToTextField(_ action: Selector) -> Bool {
        guard isEditingText else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }

    private func closeWindow() async {
        let window = NSApp.keyWindow
        if window?.identifier?.rawValue.contains("main") == true || window?.title == controller.displayName {
            guard await DocumentFlows.closeCurrent(controller) else { return }
            await controller.newDocument()
        }
        window?.performClose(nil)
    }

    static func keyboardShortcut(_ shortcut: KeyShortcut) -> KeyboardShortcut {
        let key: KeyEquivalent =
            shortcut.key == KeyShortcut.deleteKey ? .delete : KeyEquivalent(Character(shortcut.key))
        var modifiers: EventModifiers = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}
