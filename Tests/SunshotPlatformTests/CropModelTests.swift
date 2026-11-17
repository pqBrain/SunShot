import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

/// The crop dialog flow through the observable model (S10). Content 200×100.
@MainActor
@Suite("Crop dialog", .serialized)
struct CropModelTests {
    private func model() async throws -> EditorModel {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 200, height: 100), fileName: "shot.png")
        return model
    }

    @Test("[S10-AC7] the dialog edits a draft; Cancel keeps the document, Apply records one step")
    func dialogFlow() async throws {
        let empty = EditorModel()
        #expect(!empty.canCrop)
        empty.openCrop()
        #expect(!empty.crop.isPresented)

        let model = try await model()
        #expect(model.canCrop && !model.isCropped)
        model.openCrop()
        #expect(model.crop.isPresented)
        #expect(model.crop.draft == LayoutRect(x: 0, y: 0, width: 200, height: 100))
        #expect(model.cropSourceImage?.width == 200)
        let before = model.session.document
        #expect(model.crop.pointerDown(at: AnnotationPoint(x: 200, y: 100), tolerance: 6) == .bottomRight)
        model.crop.pointerDragged(dx: -50, dy: -20)
        model.crop.pointerUp()
        #expect(model.crop.draft == LayoutRect(x: 0, y: 0, width: 150, height: 80))
        #expect(model.crop.sizeLabel == "150 × 80 px" && model.crop.isCropping)
        #expect(model.session.document == before, "dragging only changes the draft")
        model.cancelCrop()
        #expect(!model.crop.isPresented && model.session.document == before)

        model.openCrop()
        model.crop.setAspect(.square)
        #expect(model.crop.draft == LayoutRect(x: 50, y: 0, width: 100, height: 100))
        model.crop.pointerDragged(dx: 10, dy: 10)  // no handle grabbed: ignored
        #expect(model.crop.pointerDown(at: AnnotationPoint(x: -50, y: -50), tolerance: 6) == nil)
        await model.applyCrop().value
        #expect(!model.crop.isPresented)
        #expect(model.session.crop == CropRect(x: 50, y: 0, width: 100, height: 100))
        #expect(model.undoTitle == "Undo Crop Image")
        #expect(model.preview?.width == 100 + 2 * Int(SunshotDefaults.padding))

        // Re-opening shows the full image with the current crop; Reset goes back to the whole image.
        model.openCrop()
        #expect(model.crop.imageSize == PixelSize(width: 200, height: 100))
        #expect(model.crop.draft == LayoutRect(x: 50, y: 0, width: 100, height: 100))
        model.crop.reset()
        #expect(model.crop.aspect == .free && !model.crop.isCropping)
        await model.applyCrop().value
        #expect(!model.isCropped && model.undoTitle == "Undo Remove Crop")
        await model.undo()
        #expect(model.isCropped)
        await model.removeCrop().value
        #expect(!model.isCropped)
    }

    @Test("[S10-AC7] Crop… is disabled in Annotate mode")
    func disabledInAnnotate() async throws {
        let model = try await model()
        model.setAnnotateMode(true)
        #expect(!model.canCrop)
        model.openCrop()
        #expect(!model.crop.isPresented)
    }

    @Test("[S10-AC9] Annotate mode on a cropped image stores uncropped content pixels")
    func annotateCropped() async throws {
        let model = try await model()
        await model.perform { $0.setCrop(CropRect(x: 50, y: 20, width: 100, height: 60)) }.value
        // Canvas 100 + 128 by 60 + 128, displayed at full size.
        let width = 228.0
        let height = 188.0
        let mapping = try #require(model.annotationMapping(viewWidth: width, viewHeight: height))
        #expect(mapping.origin == AnnotationPoint(x: 50, y: 20))
        #expect(mapping.contentSize == PixelSize(width: 100, height: 60))
        model.setAnnotateMode(true)
        model.selectTool(.rectangle)
        model.annotationPointerDown(x: 64 + 10, y: 64 + 10, viewWidth: width, viewHeight: height)
        model.annotationPointerDragged(x: 64 + 40, y: 64 + 30, viewWidth: width, viewHeight: height, snap: false)
        model.annotationPointerUp()
        let rectangle = try #require(model.session.annotations.items.first)
        #expect(rectangle.points == [AnnotationPoint(x: 60, y: 30), AnnotationPoint(x: 90, y: 50)])
        #expect(model.titleBarUnitRect == nil)
    }

    @Test("[S10-AC17] Crop… is a menu item enabled only with image content")
    func cropMenu() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        #expect(!controller.isEnabled(.crop))
        await controller.model.importData(try TestImages.png())
        #expect(controller.isEnabled(.crop))
        #expect(controller.isEnabled(.captureArea) && controller.isEnabled(.captureWindow))
        #expect(controller.isEnabled(.captureWebsite))
    }
}
