import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Canvas interaction (model)", .serialized)
struct CanvasInteractionTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        model.layout.reduceMotion = { false }
        await model.importData(try TestImages.png(width: 160, height: 100), fileName: "shot.png")
        try #require(model.hasContent)
        return model
    }

    @Test("[S6-AC21] the preview tells the screenshot from the backdrop; drag on it moves the content")
    func regionAndMove() async throws {
        let model = try await loadedModel()
        let size = try #require(model.session.canvasSize)
        let (width, height) = (Double(size.width) / 2, Double(size.height) / 2)  // displayed at half size
        #expect(model.canvasRegion(x: width / 2, y: height / 2, viewWidth: width, viewHeight: height) == .content)
        #expect(model.canvasRegion(x: 1, y: 1, viewWidth: width, viewHeight: height) == .backdrop)
        #expect(model.canvasRegion(x: 1, y: 1, viewWidth: 0, viewHeight: height) == nil)
        // The main preview is the drag surface.
        model.beginPositionDrag(surfaceWidth: width, surfaceHeight: height)
        model.updatePositionDrag(translationX: width * 0.2, translationY: height * 0.3, modifiers: [.option, .command])
        model.endPositionDrag()
        #expect(abs(model.session.contentTransform.x - 0.2) < 1e-9)
        #expect(abs(model.session.contentTransform.y - 0.3) < 1e-9)
        #expect(model.undoTitle == "Undo Move Content")
        // Moved: the old centre is backdrop now.
        #expect(model.canvasRegion(x: width / 2, y: height / 2, viewWidth: width, viewHeight: height) == .backdrop)
    }

    @Test("[S6-AC22] pinch and twist are one undo step each")
    func pinchAndTwist() async throws {
        let model = try await loadedModel()
        model.updatePinch(magnification: 2)
        #expect(model.session.contentTransform.zoom == 100)
        model.beginPinch()
        model.beginPinch()
        model.updatePinch(magnification: 1.2)
        model.updatePinch(magnification: 1.5)
        model.endPinch()
        model.endPinch()
        #expect(model.session.contentTransform.zoom == 150)
        #expect(model.undoTitle == "Undo Change Zoom")
        model.beginTwist()
        model.updateTwist(degrees: 10)
        model.updateTwist(degrees: 88)
        model.endTwist()
        #expect(model.session.contentTransform.rotation == 90)
        #expect(model.undoTitle == "Undo Rotate Content")
        model.beginTwist()
        model.updateTwist(degrees: 2, snaps: false)
        model.endTwist()
        #expect(model.session.contentTransform.rotation == 92)
        await model.undo()
        await model.undo()
        #expect(model.session.contentTransform.rotation == 0)
        await model.undo()
        #expect(model.session.contentTransform.zoom == 100)
        model.updateTwist(degrees: 30)
        #expect(model.session.contentTransform.rotation == 0)
    }

    @Test("[S6-AC23] clicks reveal the Backdrop or Border section, repeatably, and show the inspector")
    func clickFocus() async throws {
        let model = try await loadedModel()
        model.showsInspector = false
        model.canvasClicked(.backdrop)
        #expect(model.showsInspector)
        #expect(model.inspectorFocus?.section == .backdrop)
        let first = try #require(model.inspectorFocus)
        model.canvasClicked(.backdrop)
        #expect(model.inspectorFocus != first)
        model.canvasClicked(.content)
        #expect(model.inspectorFocus?.section == .border)
    }

    @Test("[S6-AC24] a larger display renders a sharper preview; a smaller one a smaller, cheaper one")
    func displaySizedPreview() async throws {
        let model = try await loadedModel()
        let size = try #require(model.session.canvasSize)
        #expect(model.previewScale == 1)
        model.setPreviewDisplay(width: Double(size.width) * 3, height: Double(size.height) * 3)
        #expect(model.previewScale >= 3)
        await model.refreshPreview()
        let preview = try #require(model.preview)
        #expect(Double(preview.width) >= Double(size.width) * 3 - 1)
        // Smaller than the canvas: rendered at the shown size (one 128 px step on the long side here).
        model.setPreviewDisplay(width: 10, height: 10)
        #expect(model.previewScale < 1)
        #expect(model.previewScale * Double(max(size.width, size.height)) == PreviewSizing.quantum)
        await model.refreshPreview()
        #expect(try #require(model.preview).width < size.width)
        model.setPreviewDisplay(width: 0, height: 0)
        #expect(model.previewDisplayPixels == nil)
    }
}
