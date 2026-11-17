import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Picking a screenshot on the canvas", .serialized)
struct ScreenshotPickTests {
    private func centre(_ corners: [LayoutPoint]) -> LayoutPoint {
        LayoutPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
    }

    @Test("[S16-AC14] click a screenshot of a layout to pick it; Delete or its × removes it as one undo step")
    func pickAndDelete() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let model = fixture.controller.model
        await model.importData(try TestImages.png(width: 400, height: 250))
        #expect(model.screenshotNumber(x: 10, y: 10, viewWidth: 100, viewHeight: 100) == nil, "one screenshot")
        await model.setCollage("side-by-side").value
        let folder = try TempDirectory()
        defer { folder.cleanUp() }
        let file = folder.file("second.png")
        try TestImages.png(width: 300, height: 200, red: 0.9).write(to: file)
        await model.importSlotFile(at: file, number: 1)
        let canvas = try #require(model.session.canvasSize)
        let (width, height) = (Double(canvas.width), Double(canvas.height))

        // Each screenshot's outline centre picks that screenshot; the backdrop corner picks none.
        for number in [0, 1] {
            model.layout.selectedScreenshot = number
            let outline = try #require(model.pickedScreenshotOutline(viewWidth: width, viewHeight: height))
            let point = centre(outline)
            #expect(model.screenshotNumber(x: point.x, y: point.y, viewWidth: width, viewHeight: height) == number)
        }
        model.pickScreenshot(x: 1, y: 1, viewWidth: width, viewHeight: height)
        #expect(model.selectedScreenshot == nil)
        #expect(!model.deletePickedScreenshot())

        // Moved and rotated, the second screenshot is still found under its outline.
        await model.perform { $0.setRotation(20) }.value
        model.layout.selectedScreenshot = 1
        let turned = centre(try #require(model.pickedScreenshotOutline(viewWidth: width, viewHeight: height)))
        model.clearScreenshotPick()
        model.pickScreenshot(x: turned.x, y: turned.y, viewWidth: width, viewHeight: height)
        #expect(model.selectedScreenshot == 1)

        #expect(model.deletePickedScreenshot())
        await Task.yield()
        #expect(model.undoTitle == "Undo Remove Screenshot")
        #expect(model.collage == nil && model.selectedScreenshot == nil)
        #expect(model.mainImage?.width == 400)
        await model.undo()
        #expect(model.collage?.id == "side-by-side" && model.screenshotRows[1].image != nil)

        // A tilted layout isn't hit-tested.
        await model.perform { $0.setTilt(x: 20, y: 0) }.value
        #expect(model.screenshotNumber(x: turned.x, y: turned.y, viewWidth: width, viewHeight: height) == nil)
    }

    @Test("[S16-AC15] a picked screenshot dragged onto another swaps places as one step and stays picked")
    func reorder() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let model = fixture.controller.model
        await model.importData(try TestImages.png(width: 400, height: 250))
        await model.setCollage("side-by-side").value
        let folder = try TempDirectory()
        defer { folder.cleanUp() }
        let file = folder.file("second.png")
        try TestImages.png(width: 300, height: 200, red: 0.9).write(to: file)
        await model.importSlotFile(at: file, number: 1)
        let canvas = try #require(model.session.canvasSize)
        let (width, height) = (Double(canvas.width), Double(canvas.height))
        let first = centre(try #require(model.screenshotOutline(number: 0, viewWidth: width, viewHeight: height)))
        let second = centre(try #require(model.screenshotOutline(number: 1, viewWidth: width, viewHeight: height)))

        #expect(model.reorderTarget(x: second.x, y: second.y, viewWidth: width, viewHeight: height) == nil)
        model.pickScreenshot(x: first.x, y: first.y, viewWidth: width, viewHeight: height)
        #expect(model.reorderTarget(x: first.x, y: first.y, viewWidth: width, viewHeight: height) == nil)
        #expect(model.reorderTarget(x: second.x, y: second.y, viewWidth: width, viewHeight: height) == 1)
        #expect(!model.dropPickedScreenshot(x: 1, y: 1, viewWidth: width, viewHeight: height), "onto the backdrop")

        #expect(model.dropPickedScreenshot(x: second.x, y: second.y, viewWidth: width, viewHeight: height))
        await Task.yield()
        #expect(model.undoTitle == "Undo Move Screenshot")
        #expect(model.mainImage?.width == 300 && model.screenshotRows[1].image?.width == 400)
        #expect(model.selectedScreenshot == 1)
    }
}
