import AppKit
import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing
import UniformTypeIdentifiers

@testable import SunshotPlatform

/// S15: the Screenshots inspector section's model — rows, layout choice, choosing, dropping and removing images.
@MainActor
@Suite("Screenshots in the editor", .serialized)
struct ScreenshotsModelTests {
    @Test("[S15-AC5] rows follow the layout; files and drops fill a slot; rows swap and remove")
    func rows() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let model = fixture.controller.model
        await model.importData(try TestImages.png(width: 400, height: 250))
        #expect(model.screenshotRows.map(\.name) == ["Main"])
        #expect(model.mainImage != nil && model.collage == nil)

        await model.setCollage("cascade").value
        #expect(model.collage?.id == "cascade" && model.undoTitle == "Undo Change Screenshot Layout")
        #expect(model.screenshotRows.map(\.name) == ["Main", "Screenshot 2", "Screenshot 3"])
        #expect(model.screenshotRows.map(\.slot.number) == [0, 1, 2])
        #expect(model.screenshotRows.allSatisfy { $0.image == nil })

        let folder = try TempDirectory()
        defer { folder.cleanUp() }
        let file = folder.file("second.png")
        try TestImages.png(width: 60, height: 40, red: 0.9).write(to: file)
        await model.importSlotFile(at: file, number: 1)
        #expect(model.screenshotRows[1].image?.width == 60 && model.undoTitle == "Undo Set Screenshot")
        #expect(await model.importDroppedSlot([folder.file("notes.txt"), file], number: 2))
        #expect(model.screenshotRows[2].image != nil)
        #expect(await !model.importDroppedSlot([folder.file("notes.txt")], number: 2))

        await model.importSlotFile(at: folder.file("missing.png"), number: 2)
        #expect(model.alert?.title == UIStrings.screenshotFailedTitle)

        #expect(model.canRemoveScreenshot(0) && model.canRemoveScreenshot(1) && model.canRemoveScreenshot(2))
        await model.moveScreenshot(from: 2, to: 1).value
        #expect(model.undoTitle == "Undo Move Screenshot")
        await model.removeScreenshot(at: 1).value
        #expect(model.undoTitle == "Undo Remove Screenshot" && model.collage?.id == "overlap")
        await model.removeScreenshot(at: 0).value
        #expect(model.collage == nil && !model.canRemoveScreenshot(0))
        #expect(model.screenshotRows.count == 1)

        await model.setDevice("phone").value
        #expect(model.collage == nil && model.screenshotRows.count == 1)
        await model.setCollage(nil).value
    }

    @Test("[S15-AC4] the inline title editor sits on the main screenshot's title bar")
    func titleBar() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let model = fixture.controller.model
        await model.importData(try TestImages.png(width: 400, height: 250))
        await model.perform { $0.setFrameKind(.macWindow) }.value
        let single = try #require(model.titleBarUnitRect)
        await model.setCollage("row").value
        let row = try #require(model.titleBarUnitRect)
        // Three screenshots in a row: the main one is the left third.
        #expect(row.width < single.width / 2 && row.maxX < 0.4 && row.minX > 0)
        #expect(abs(row.minY - single.minY) < 1e-6)
    }

    @Test("[S15-AC14] pasted screenshots lose a solid border; the notice says so")
    func pasteTrims() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let model = fixture.controller.model
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sunshot-trim-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        func paste(_ data: Data) async {
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            await model.paste(from: pasteboard)
        }
        await paste(try Self.framedPNG())
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 70, height: 50))
        #expect(model.session.document.content?.data == nil)
        #expect(model.notice == UIStrings.screenshotTrimmed)
        await paste(try Self.framedPNG())
        #expect(model.session.document.slots[1]?.pixelSize == PixelSize(width: 70, height: 50))
        #expect(model.notice == "Added as screenshot 2 · Side by Side · border trimmed")
        await paste(try TestImages.png(width: 40, height: 30))
        #expect(model.notice == "Added as screenshot 3 · Row of Three")
    }

    /// A 120×80 PNG: a 70×50 dark block on a light border.
    static func framedPNG() throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw TestError.setup }
        context.setFillColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 20, y: 10, width: 70, height: 50))
        guard let image = context.makeImage() else { throw TestError.setup }
        return try TestImages.encode(image, as: .png)
    }

    @Test("[S15-AC9] Screenshots copy")
    func strings() {
        #expect(UIStrings.screenshotsHint(hasDevice: true, multiple: true) == UIStrings.screenshotsDeviceHint)
        #expect(UIStrings.screenshotsHint(hasDevice: true, multiple: false) == UIStrings.screenshotsDeviceLayoutHint)
        #expect(UIStrings.screenshotsHint(hasDevice: false, multiple: true) == UIStrings.screenshotsSlotsHint)
        #expect(UIStrings.screenshotsHint(hasDevice: false, multiple: false) == UIStrings.screenshotsLayoutHint)
        #expect(UIStrings.screenshotName(number: 1) == "Screenshot 2")
        #expect(UIStrings.screenshotName(number: 0) == "Main")
        #expect(UIStrings.screenshotAdded(number: 1, layout: "Side by Side") == "Added as screenshot 2 · Side by Side")
        #expect(UIStrings.screenshotAdded(number: 2, layout: nil) == "Added as screenshot 3")
        #expect(ScreenshotDrag.number(from: ScreenshotDrag.payload(number: 3)) == 3)
        #expect(
            ScreenshotDrag.number(from: "hello") == nil && ScreenshotDrag.number(from: "sunshot-screenshot:-1") == nil)
        #expect(UIStrings.screenshotsFull(count: 4) == "All 4 screenshots are filled. Remove one to add another.")
        #expect(UIStrings.screenshotRow("Screenshot 2", hasImage: false) == "Screenshot 2, shows the main image")
        #expect(UIStrings.screenshotRow("Main", hasImage: true) == "Main")
        #expect(UIStrings.screenshotChooseAccessibility("Screenshot 2") == "Choose image for Screenshot 2")
        #expect(UIStrings.screenshotRemoveAccessibility("Screenshot 2") == "Remove image from Screenshot 2")
    }
}
