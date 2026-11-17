import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

/// Annotate mode through the observable model. Content 200×100 with the default 64 px padding → canvas 328×228,
/// displayed at full size (view points = canvas pixels), so content (x, y) is view (x + 64, y + 64).
@MainActor
@Suite("Annotate mode", .serialized)
struct AnnotateModelTests {
    private let width = 328.0
    private let height = 228.0

    private func annotatingModel() async throws -> EditorModel {
        let model = EditorModel()
        model.setAnnotateMode(true)
        #expect(!model.annotate.isActive, "no content → can't annotate")
        await model.importData(try TestImages.png(width: 200, height: 100), fileName: "shot.png")
        model.setAnnotateMode(true)
        try #require(model.annotate.isActive)
        return model
    }

    private func drag(
        _ model: EditorModel, from: (Double, Double), to points: [(Double, Double)], additive: Bool = false
    ) {
        model.annotationPointerDown(
            x: from.0 + 64, y: from.1 + 64, viewWidth: width, viewHeight: height, additive: additive)
        for point in points {
            model.annotationPointerDragged(
                x: point.0 + 64, y: point.1 + 64, viewWidth: width, viewHeight: height, snap: false)
        }
        model.annotationPointerUp()
    }

    @Test("[S9-AC1] enter / leave Annotate mode, tool keys and Esc")
    func modeAndKeys() async throws {
        let model = try await annotatingModel()
        #expect(model.annotate.tool == .pen)
        #expect(model.handleAnnotateKey(.character("R")))
        #expect(model.annotate.tool == .rectangle)
        #expect(model.handleAnnotateKey(.character("v")))
        #expect(model.annotate.tool == .select)
        #expect(!model.handleAnnotateKey(.character("z")))
        #expect(
            AnnotationTool.allCases.map(UIStrings.toolLabel) == [
                "Select, V", "Pen, P", "Highlighter, H", "Eraser, E", "Arrow, A", "Rectangle, R", "Text, T", "Steps, S",
                "Redact, B", "Sticker, ⌥⌘S",
            ])
        #expect(Set(AnnotationTool.allCases.map(UIStrings.toolSymbol)).count == AnnotationTool.allCases.count)
        #expect(model.handleAnnotateKey(.escape))
        #expect(!model.annotate.isActive)
        #expect(!model.handleAnnotateKey(.character("p")), "keys are ignored outside Annotate mode")
        model.toggleAnnotateMode()
        #expect(model.annotate.isActive)
        model.toggleAnnotateMode()
        #expect(!model.annotate.isActive)
    }

    @Test("[S9-AC6] a pen drag through the model is one undo entry and shows in the preview")
    func penThroughModel() async throws {
        let model = try await annotatingModel()
        drag(model, from: (20, 20), to: [(40, 30), (60, 50), (90, 50)])
        #expect(model.session.annotations.items.count == 1)
        #expect(model.undoTitle == "Undo Draw")
        #expect(model.session.history.undoCount == 2, "import + one drawing")
        #expect(!model.annotate.isDragging)
        await model.refreshPreview()
        #expect(model.preview != nil)
        await model.undo()
        #expect(!model.hasAnnotations)
    }

    @Test("[S9-AC15] [ ] change the size; ⇧1–3 the line style; F the fill; changes apply to the selection")
    func styleKeys() async throws {
        let model = try await annotatingModel()
        model.selectTool(.rectangle)
        drag(model, from: (10, 10), to: [(80, 60)])
        let id = try #require(model.session.annotations.items.first?.id)
        model.selectTool(.select)
        drag(model, from: (10, 30), to: [])
        #expect(model.annotationSelection == [id])
        let entries = model.session.history.undoCount
        model.handleAnnotateKey(.character("]"))
        #expect(model.annotate.style.size == .large)
        #expect(model.session.annotations.items.first?.lineWidth == 12)
        model.handleAnnotateKey(.character("["))
        model.handleAnnotateKey(.character("["))
        #expect(model.annotate.style.size == .small)
        model.handleAnnotateKey(.character("@"))
        #expect(model.session.annotations.items.first?.lineStyle == .dashed)
        model.handleAnnotateKey(.character("3"), shift: true)
        #expect(model.annotate.style.lineStyle == .dotted)
        model.handleAnnotateKey(.character("1"), shift: true)
        model.handleAnnotateKey(.character("#"))
        model.handleAnnotateKey(.character("2"), shift: true)
        model.handleAnnotateKey(.character("!"))
        #expect(model.annotate.style.lineStyle == .solid)
        model.handleAnnotateKey(.character("f"))
        #expect(model.session.annotations.items.first?.filled == true)
        #expect(model.session.history.undoCount == entries + 10)
        model.setRedactionMode(.blur)
        model.setTextAlignment(.center)
        #expect(model.session.annotations.items.first?.redaction == .blur)
        model.setAnnotationColor(AnnotationDefaults.palette[15].color)
        model.finishContinuousEdit()
        #expect(model.session.annotations.items.first?.color == RGBAColor(rgb: 0x3366E8))
        #expect(model.undoTitle == "Undo Change Annotation Style")
        model.setStepFormat(.letters)
        #expect(model.stepFormat == .letters)
    }

    @Test("[S9-AC16] [S9-AC17] select, ⌘-click, move, and the overlay chrome follows")
    func selectAndMove() async throws {
        let model = try await annotatingModel()
        model.selectTool(.rectangle)
        model.setAnnotationFilled(true)
        drag(model, from: (10, 10), to: [(50, 50)])
        drag(model, from: (120, 10), to: [(160, 50)])
        let ids = model.session.annotations.items.map(\.id)
        model.selectTool(.select)
        drag(model, from: (20, 20), to: [])
        #expect(model.annotationSelection == [ids[0]])
        #expect(model.selectionHandles(viewWidth: width, viewHeight: height).count == 5)
        drag(model, from: (130, 20), to: [], additive: true)
        #expect(model.annotationSelection == Set(ids))
        #expect(model.selectionHandles(viewWidth: width, viewHeight: height).isEmpty, "no handles for several")
        let entries = model.session.history.undoCount
        drag(model, from: (20, 20), to: [(25, 25), (30, 40)])
        #expect(model.session.history.undoCount == entries + 1)
        #expect(model.undoTitle == "Undo Move Annotation")
        let outlines = model.selectionOutlines(viewWidth: width, viewHeight: height)
        #expect(outlines.count == 2)
        let first = try #require(outlines.first { $0.id == ids[0] })
        #expect(first.centerX == 64 + 30 + 10 && first.centerY == 64 + 30 + 20 && first.width == 40)
        drag(model, from: (300, 90), to: [])
        #expect(model.annotationSelection.isEmpty)
    }

    @Test("[S9-AC18] ⌘D duplicates and selects the copies; ⌫ deletes; ⌘⌫ clears in Annotate mode")
    func commands() async throws {
        let model = try await annotatingModel()
        model.selectTool(.step)
        drag(model, from: (30, 30), to: [])
        #expect(model.undoTitle == "Undo Add Step")
        model.selectTool(.select)
        drag(model, from: (30, 30), to: [])
        let original = model.annotationSelection
        model.duplicateSelectedAnnotations()
        #expect(model.session.annotations.items.count == 2)
        #expect(model.annotationSelection.isDisjoint(with: original) && model.annotationSelection.count == 1)
        model.handleAnnotateKey(.delete)
        #expect(model.session.annotations.items.count == 1)
        #expect(model.undoTitle == "Undo Delete Annotation")
        #expect(model.clearCommandTitle == "Clear Annotations")
        #expect(model.canClear)
        await model.clearCommand()
        #expect(!model.hasAnnotations)
        #expect(model.hasContent, "⌘⌫ in Annotate mode keeps the content")
        await model.undo()
        #expect(model.hasAnnotations)
        model.setAnnotateMode(false)
        #expect(model.clearCommandTitle == "Clear Content")
        await model.clearCommand()
        #expect(!model.hasContent)
    }

    @Test("[S9-AC11] text: click opens the editor, Return commits one entry, double-click edits")
    func text() async throws {
        let model = try await annotatingModel()
        model.selectTool(.text)
        drag(model, from: (20, 20), to: [])
        let editing = try #require(model.annotate.textEditing)
        #expect(editing.id == nil)
        let placement = try #require(model.textEditorPlacement(viewWidth: width, viewHeight: height))
        #expect(placement.x == 84 && placement.y == 84 && placement.fontSize == 24)
        #expect(!model.handleAnnotateKey(.character("p")), "typing goes to the text field, not the tools")
        model.annotate.textEditing?.text = "Note"
        model.commitTextEditing()
        #expect(model.undoTitle == "Undo Add Text")
        let id = try #require(model.session.annotations.items.first?.id)
        model.selectTool(.select)
        model.annotationPointerDown(x: 90, y: 90, viewWidth: width, viewHeight: height, clickCount: 2)
        #expect(model.annotate.textEditing?.id == id)
        #expect(model.annotate.textEditing?.text == "Note")
        #expect(model.handleAnnotateKey(.escape), "Esc closes the editor first")
        #expect(model.annotate.textEditing == nil && model.annotate.isActive)
        model.selectTool(.text)
        drag(model, from: (22, 22), to: [])
        #expect(model.annotate.textEditing?.id == id)
        model.cancelTextEditing()
        #expect(model.session.annotations.items.first?.text == "Note")
    }

    @Test("[S9-AC14] picking a sticker switches to the sticker tool and a click places it")
    func stickers() async throws {
        let model = try await annotatingModel()
        model.annotate.showsStickerPicker = true
        model.chooseSticker("🎉")
        #expect(model.annotate.tool == .sticker && !model.annotate.showsStickerPicker)
        drag(model, from: (100, 50), to: [])
        #expect(model.session.annotations.items.first?.text == "🎉")
        #expect(model.undoTitle == "Undo Add Sticker")
        #expect(model.annotationMapping(viewWidth: width, viewHeight: height)?.contentLongEdge == 200)
        #expect(UIStrings.sizeName(.large) == "L" && UIStrings.redactionName(.blur) == "Blur")
        #expect(AnnotationLineStyle.allCases.map(UIStrings.lineStyleName) == ["Solid, ⇧1", "Dashed, ⇧2", "Dotted, ⇧3"])
        #expect(StepFormat.allCases.map(UIStrings.stepFormatName) == ["1 2 3", "A B C"])
        #expect(AnnotationTextAlignment.allCases.map(UIStrings.alignmentName).count == 3)
    }

    @Test("[S9-AC8] erasing through the model is one entry; leaving the mode mid-drag closes the drag")
    func eraseAndLeave() async throws {
        let model = try await annotatingModel()
        drag(model, from: (10, 50), to: [(190, 50)])
        drag(model, from: (10, 80), to: [(190, 80)])
        model.selectTool(.eraser)
        let entries = model.session.history.undoCount
        drag(model, from: (100, 30), to: [(100, 60)])
        #expect(model.session.annotations.items.count == 1)
        #expect(model.session.history.undoCount == entries + 1)
        #expect(model.undoTitle == "Undo Erase")
        model.selectTool(.pen)
        model.annotationPointerDown(x: 70, y: 70, viewWidth: width, viewHeight: height)
        #expect(model.annotate.isDragging)
        model.setAnnotateMode(false)
        #expect(!model.annotate.isDragging)
        model.annotationPointerDown(x: 70, y: 70, viewWidth: width, viewHeight: height)
        #expect(!model.annotate.isDragging, "pointer input is ignored outside Annotate mode")
    }
}
