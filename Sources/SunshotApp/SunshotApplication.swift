import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI
import UniformTypeIdentifiers

struct SunshotApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Sunshot", id: Studio.windowID) {
            StudioWindowContent(appDelegate: appDelegate)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { SunshotCommands(controller: appDelegate.controller) }
        .commands { BulkCommands(bulk: appDelegate.bulk) }
        .commands { AnnotateCommands(model: appDelegate.controller.model) }
        Settings {
            SettingsView(controller: appDelegate.controller, hotkey: appDelegate.hotkey)
        }
        // S16: Sunshot lives in the menu bar too, so the capture shortcut keeps working with no window open.
        MenuBarExtra(isInserted: menuBarIconShown) {
            MenuBarContent(controller: appDelegate.controller)
        } label: {
            Label(UIStrings.menuBarTitle, systemImage: "camera.aperture")
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIconShown: Binding<Bool> {
        Binding(
            get: { appDelegate.controller.settings.showsMenuBarIcon },
            set: { shown in
                // SwiftUI writes this back while it updates scenes; writing an unchanged value would still notify
                // `settings` observers and re-enter that update (recursing until the stack runs out).
                guard appDelegate.controller.settings.showsMenuBarIcon != shown else { return }
                appDelegate.controller.settings.showsMenuBarIcon = shown
            })
    }
}

/// The studio window's content; it also hands `openWindow` to `Studio`, so the menu bar and the capture shortcut
/// can reopen the window after it was closed.
private struct StudioWindowContent: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        EditorView(model: appDelegate.controller.model)
            .safeAreaInset(edge: .bottom, spacing: 0) { BulkStripView(bulk: appDelegate.bulk) }
            .environment(appDelegate.controller)
            .navigationTitle(appDelegate.controller.displayName)
            .frame(minWidth: 820, minHeight: 540)
            .onAppear {
                Studio.openWindow = openWindow
                // Outside the scene update: changing the policy mid-update re-enters SwiftUI's scene graph.
                Task { @MainActor in
                    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
                }
            }
    }
}

/// Open and save panels (AppKit, so the save panel can start in Pictures with the templated file name).
@MainActor
enum Panels {
    static func openImage(into model: EditorModel) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageTypes.supported
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.importFile(at: url)
    }

    static func chooseBackdropImage(for model: EditorModel) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageTypes.supported
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.importBackdropFile(at: url)
    }

    /// S15: an image for one slot of a screenshot layout or multi-device layout.
    static func chooseSlotImage(for model: EditorModel, number: Int) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageTypes.supported
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.importSlotFile(at: url, number: number)
    }
}
