import AppKit
import SunshotPlatform
import SwiftUI

/// S14 menu items, kept apart from the main command groups: File ▸ Import Multiple…, Export All…, Close Batch.
struct BulkCommands: Commands {
    let bulk: BulkSession

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(UIStrings.importMultiple) { Task { await BulkPanels.importMultiple(into: bulk) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .importExport) {
            Button(UIStrings.exportAll) { Task { await BulkPanels.exportAll(from: bulk) } }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(!bulk.canExportAll)
            Button(UIStrings.closeBatch) { bulk.close() }
                .disabled(!bulk.isActive || bulk.isExporting)
        }
    }
}

/// Open panels for the batch (several files and folders in; one folder out).
@MainActor
enum BulkPanels {
    static func importMultiple(into bulk: BulkSession) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageTypes.supported
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = UIStrings.importMultiplePrompt
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        await bulk.importURLs(panel.urls)
    }

    static func exportAll(from bulk: BulkSession) async {
        guard bulk.canExportAll else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = UIStrings.exportHere
        panel.message = UIStrings.chooseExportFolder
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        await bulk.exportAll(to: folder)
    }
}
