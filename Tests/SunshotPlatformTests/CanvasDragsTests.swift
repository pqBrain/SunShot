import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Canvas drags (model)", .serialized)
struct CanvasDragsModelTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        model.layout.reduceMotion = { false }
        await model.importData(try TestImages.png(width: 160, height: 100), fileName: "shot.png")
        try #require(model.hasContent)
        return model
    }

    private func canvas(_ model: EditorModel) throws -> CanvasLayout {
        let size = try #require(model.session.document.imageContentSize)
        return CanvasLayout.compute(contentSize: size, project: model.project)
    }

    @Test("[S6-AC25] dragging the backdrop outward grows the padding as one undo step")
    func padding() async throws {
        let model = try await loadedModel()
        let layout = try canvas(model)
        let (width, height) = (Double(layout.canvasSize.width), Double(layout.canvasSize.height))
        let start = model.project.padding
        model.updatePaddingDrag(translationX: -10, translationY: 0)
        #expect(model.project.padding == start)
        model.beginPaddingDrag(x: 2, y: height / 2, viewWidth: width, viewHeight: height)
        model.beginPaddingDrag(x: 2, y: height / 2, viewWidth: width, viewHeight: height)
        model.updatePaddingDrag(translationX: -5, translationY: 0)
        model.updatePaddingDrag(translationX: -20, translationY: 3)
        model.endPaddingDrag()
        model.endPaddingDrag()
        #expect(model.project.padding == start + 20)
        #expect(model.undoTitle == "Undo Change Padding")
        await model.undo()
        #expect(model.project.padding == start)
        model.perform { $0.setPadding(.nan) }
        #expect(model.project.padding == start)
        model.perform { $0.setPadding(-4) }
        #expect(model.project.padding == 0)
    }

    @Test("[S6-AC26] ⇧-drag on the screenshot tilts it as one undo step")
    func tilt() async throws {
        let model = try await loadedModel()
        model.updateTiltDrag(translationX: 100, translationY: 0)
        #expect(model.session.contentTransform.isFlat)
        model.beginTiltDrag()
        model.beginTiltDrag()
        model.updateTiltDrag(translationX: 50, translationY: 0)
        model.updateTiltDrag(translationX: 100, translationY: -100)
        model.endTiltDrag()
        model.endTiltDrag()
        #expect(model.session.contentTransform.tiltY == 15)
        #expect(model.session.contentTransform.tiltX == 15)
        #expect(model.undoTitle == "Undo Tilt Content")
    }

    @Test("[S6-AC27] the corner handle sits radius in from the corner, sets the radius, hides when transformed")
    func cornerHandle() async throws {
        let model = try await loadedModel()
        let layout = try canvas(model)
        let viewWidth = Double(layout.canvasSize.width) * 2
        let viewHeight = Double(layout.canvasSize.height) * 2
        model.perform {
            $0.setCornerStyle(.smooth)
            $0.setCornerRadius(24)
        }
        let point = try #require(model.cornerHandlePoint(viewWidth: viewWidth, viewHeight: viewHeight))
        #expect(abs(point.x - (layout.frameRect.x * 2 + 48)) < 1e-6)
        #expect(abs(point.y - (layout.frameRect.y * 2 + 48)) < 1e-6)
        model.beginCornerDrag()
        model.updateCornerDrag(translationX: 10, translationY: 10, viewWidth: viewWidth, viewHeight: viewHeight)
        model.endCornerDrag()
        #expect(model.project.border.radius == 29)
        #expect(model.undoTitle == "Undo Change Corner Radius")
        // Sharp corners become smooth once dragged.
        model.perform { $0.setCornerStyle(.sharp) }
        model.beginCornerDrag()
        model.updateCornerDrag(translationX: 8, translationY: 8, viewWidth: viewWidth, viewHeight: viewHeight)
        model.endCornerDrag()
        #expect(model.project.border.style == .smooth && model.project.border.radius == 4)
        // Too small on screen, rotated or tilted: no handle.
        #expect(model.cornerHandlePoint(viewWidth: 40, viewHeight: 30) == nil)
        model.perform { $0.setRotation(10) }
        #expect(model.cornerHandlePoint(viewWidth: viewWidth, viewHeight: viewHeight) == nil)
        model.updateCornerDrag(translationX: 8, translationY: 8, viewWidth: viewWidth, viewHeight: viewHeight)
        #expect(model.project.border.radius == 4)
    }

    @Test("[S6-AC28] double-click on the screenshot opens Crop; on the backdrop it does nothing")
    func doubleClick() async throws {
        let model = try await loadedModel()
        model.canvasDoubleClicked(.backdrop)
        #expect(!model.crop.isPresented)
        model.canvasDoubleClicked(.content)
        #expect(model.crop.isPresented)
    }

    @Test("[S6-AC28] one image dropped on the backdrop becomes the backdrop; on the screenshot it replaces it")
    func drops() async throws {
        let model = try await loadedModel()
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "drop.png")
        try TestImages.png(width: 60, height: 40).write(to: url)
        #expect(await model.importDropped([url], on: .backdrop))
        #expect(model.project.backdropSettings.kind == .image)
        #expect(model.session.document.imageContentSize == PixelSize(width: 160, height: 100))
        #expect(await model.importDropped([url], on: .content))
        #expect(model.session.document.imageContentSize == PixelSize(width: 60, height: 40))
        #expect(!(await model.importDropped([folder.appending(path: "nothing.txt")], on: .backdrop)))
    }
}
