import AppKit
import SunshotPlatform
import SwiftUI
import UniformTypeIdentifiers

struct SunshotApplication: App {
    @State private var model = EditorModel()

    var body: some Scene {
        Window("Sunshot", id: "main") {
            EditorView(model: model)
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { SunshotCommands(model: model) }
    }
}

/// Menu bar. Every action here is also reachable from the toolbar.
struct SunshotCommands: Commands {
    let model: EditorModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(UIStrings.openImage) { Task { await Panels.openImage(into: model) } }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .importExport) {
            Button(UIStrings.exportPNG) { Task { await Panels.exportPNG(from: model) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.hasContent)
        }
        CommandGroup(after: .sidebar) {
            Button(model.showsInspector ? "Hide Inspector" : "Show Inspector") { model.showsInspector.toggle() }
                .keyboardShortcut("e", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoTitle) { Task { await model.undo() } }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
            Button(model.redoTitle) { Task { await model.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }
        CommandGroup(replacing: .pasteboard) {
            Button(UIStrings.copyPNG) { Task { await model.copyPNG(to: .general) } }
                .keyboardShortcut("c")
                .disabled(!model.hasContent)
            Button(UIStrings.paste) { Task { await model.paste(from: .general) } }
                .keyboardShortcut("v")
            Divider()
            Button(UIStrings.clearContent) { Task { await model.clearContent() } }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!model.hasContent)
        }
    }
}

/// Open and save panels (AppKit, so the save panel can start in Pictures with the interim file name).
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

    static func exportPNG(from model: EditorModel) async {
        guard model.hasContent else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = model.suggestedExportName()
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.exportPNG(to: url)
    }
}
