import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing
import UniformTypeIdentifiers

@testable import SunshotPlatform

@MainActor
@Suite("Editor model", .serialized)
struct EditorModelTests {
    @Test("[S1-AC1] launch state is empty: no preview, export/copy/clear disabled, empty preview label")
    func emptyState() {
        let model = EditorModel()
        #expect(!model.hasContent && model.preview == nil)
        #expect(!model.canUndo && !model.canRedo)
        #expect(model.undoTitle == "Undo" && model.redoTitle == "Redo")
        #expect(model.previewAccessibilityLabel == "Preview, empty")
    }

    @Test("[S1-AC2] opening PNG, JPEG, HEIC, TIFF files from disk sets content and preview")
    func openFiles() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        for (type, ext) in [(UTType.png, "png"), (.jpeg, "jpg"), (.heic, "heic"), (.tiff, "tiff")] {
            let model = EditorModel()
            let url = directory.file("shot.\(ext)")
            try TestImages.encode(TestImages.solid(width: 100, height: 50), as: type).write(to: url)
            await model.importFile(at: url)
            #expect(model.alert == nil, "\(ext)")
            #expect(model.session.canvasSize == PixelSize(width: 228, height: 178))
            #expect(model.preview?.width == 228)
            #expect(model.undoTitle == "Undo Import Image")
        }
    }

    @Test("[S1-AC3] a corrupt file shows \"Can't open this file\" with file name and reason; state unchanged")
    func corruptFile() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let model = EditorModel()
        await model.importData(try TestImages.png())
        let before = model.session.document
        let url = directory.file("notes.png")
        try Data("plain text".utf8).write(to: url)

        await model.importFile(at: url)
        #expect(model.alert?.title == "Can't open this file")
        #expect(model.alert?.message.hasPrefix("notes.png: ") == true)
        #expect(model.session.document == before)
        #expect(model.session.history.undoCount == 1)

        model.alert = nil
        await model.importFile(at: directory.file("missing.png"))
        #expect(model.alert?.title == EditorModel.openFailedTitle)
    }

    @Test("[S1-AC4] drop imports the first supported file, ignores others, and notes multiple files")
    func drop() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let text = directory.file("readme.txt")
        try Data("x".utf8).write(to: text)
        let first = directory.file("a.png")
        try TestImages.png(width: 10, height: 10).write(to: first)
        let second = directory.file("b.png")
        try TestImages.png(width: 20, height: 20).write(to: second)

        let model = EditorModel()
        #expect(await model.importDroppedFiles([text]) == false)
        #expect(!model.hasContent)
        #expect(await model.importDroppedFiles([text, first, second]))
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 10, height: 10))
        #expect(model.notice == EditorModel.multipleFilesNotice)
    }

    @Test("[S1-AC14] clear, then undo and redo through the model refresh the preview")
    func clearUndoRedo() async throws {
        let model = EditorModel()
        await model.importData(try TestImages.png())
        await model.clearContent()
        #expect(!model.hasContent && model.preview == nil)
        #expect(model.undoTitle == "Undo Clear Content")
        await model.undo()
        #expect(model.hasContent && model.preview != nil)
        #expect(model.redoTitle == "Redo Clear Content")
        await model.redo()
        #expect(!model.hasContent)
    }

    @Test("[S1-AC16] importing B over A replaces it; one undo brings A back")
    func replace() async throws {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 10, height: 10))
        await model.importData(try TestImages.png(width: 30, height: 30))
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 30, height: 30))
        await model.undo()
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 10, height: 10))
    }

    @Test("[S1-AC20] preview label reads \"Preview, <W> by <H> pixels\"; control labels include shortcuts")
    func accessibility() async throws {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 1000, height: 600))
        #expect(model.previewAccessibilityLabel == "Preview, 1128 by 728 pixels")
        #expect(UIStrings.exportAccessibility == "Export as PNG, ⇧⌘E")
        #expect(UIStrings.copyAccessibility == "Copy PNG, ⌘C")
        #expect(UIStrings.chooseImageAccessibility == "Choose Image, ⌘O")
        #expect(!UIStrings.clearAccessibility.isEmpty)
        #expect(UIStrings.dropTitle == "Drop an image here" && UIStrings.pasteHint == "or press ⌘V to paste")
    }

    @Test("[S1-AC17] slow imports show progress; import decodes off the main actor")
    func progress() async throws {
        let model = EditorModel(progressDelay: .zero)
        let data = try TestImages.png(width: 3000, height: 3000)
        var sawProgress = false
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if model.showsProgress { sawProgress = true }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        await model.importData(data)
        watcher.cancel()
        #expect(sawProgress)
        #expect(!model.showsProgress && !model.isImporting)
    }
}
