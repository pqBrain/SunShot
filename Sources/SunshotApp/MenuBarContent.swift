import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// S16: bringing the studio (the editor window) forward, from the menu bar or after a capture, even when its
/// window was closed and Sunshot was running only in the menu bar.
@MainActor
enum Studio {
    static let windowID = "main"
    /// Set by the first view that can open windows (SwiftUI only hands this out inside views).
    static var openWindow: OpenWindowAction?

    static func show(_ controller: DocumentController) {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: isStudio) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: windowID)
        }
        NSApp.activate()
        if controller.settings.annotateOnOpen, controller.model.hasContent { controller.model.setAnnotateMode(true) }
    }

    static func isStudio(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.contains(windowID) == true && window.isVisible
    }
}

/// S16: the menu bar menu. Captures follow Settings ▸ After a shortcut capture (by default copied with the default
/// style); the "into Studio" items always open the capture in the editor.
struct MenuBarContent: View {
    let controller: DocumentController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let destination = controller.settings.globalCaptureDestination
        Group {
            Button(UIStrings.menuCaptureArea) { AreaCapture.start(controller: controller, destination: destination) }
                .keyboardShortcut(shortcut(.captureArea))
            Button(UIStrings.menuCaptureWindow) {
                WindowCapture.start(controller: controller, destination: destination)
            }
            .keyboardShortcut(shortcut(.captureWindow))
            Text(UIStrings.menuDestination(destination))
            Divider()
            Button(UIStrings.menuCaptureAreaToStudio) { AreaCapture.start(controller: controller) }
            Button(UIStrings.menuCaptureWindowToStudio) { WindowCapture.start(controller: controller) }
            Divider()
            Button(UIStrings.menuOpenStudio) { Studio.show(controller) }
                .keyboardShortcut(shortcut(.openStudio))
            Text(defaultStyleStatus)
            Divider()
            Button(UIStrings.menuSettings) {
                NSApp.activate()
                openSettings()
            }
            Button(UIStrings.menuHideIcon) { controller.settings.showsMenuBarIcon = false }
            Button(UIStrings.menuQuit) { NSApp.terminate(nil) }
        }
        .onAppear { if Studio.openWindow == nil { Studio.openWindow = openWindow } }
    }

    private var defaultStyleStatus: String {
        guard let style = controller.quickStyle else { return UIStrings.defaultStyleNone }
        return UIStrings.defaultStyleSaved(style.savedAt.formatted(date: .abbreviated, time: .shortened))
    }

    /// An action's global shortcut, shown next to its item (it works from anywhere, not just this menu).
    private func shortcut(_ action: GlobalShortcutAction) -> KeyboardShortcut? {
        guard let keys = controller.settings.activeShortcuts[action] else { return nil }
        guard let character = keys.keyLabel.lowercased().first, keys.keyLabel.count == 1 else { return nil }
        var modifiers: EventModifiers = []
        if keys.modifiers.contains(.command) { modifiers.insert(.command) }
        if keys.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if keys.modifiers.contains(.option) { modifiers.insert(.option) }
        if keys.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}
