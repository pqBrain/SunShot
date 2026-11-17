import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI
import UniformTypeIdentifiers

struct SunshotApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Sunshot", id: "main") {
            EditorView(model: appDelegate.controller.model)
                .safeAreaInset(edge: .bottom, spacing: 0) { BulkStripView(bulk: appDelegate.bulk) }
                .environment(appDelegate.controller)
                .navigationTitle(appDelegate.controller.displayName)
                .frame(minWidth: 820, minHeight: 540)
                .task(id: appDelegate.controller.settings.captureHotkeyEnabled) {
                    let model = appDelegate.controller.model
                    appDelegate.hotkey.setEnabled(appDelegate.controller.settings.captureHotkeyEnabled) {
                        AreaCapture.start(model: model)
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { SunshotCommands(controller: appDelegate.controller) }
        .commands { BulkCommands(bulk: appDelegate.bulk) }
        .commands { AnnotateCommands(model: appDelegate.controller.model) }
        Settings {
            SettingsView(controller: appDelegate.controller)
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
}
