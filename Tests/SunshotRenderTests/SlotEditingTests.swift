import CoreGraphics
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

/// S15: slot edits through the document store, and slot images in `.sunshot` packages.
@Suite("Multiple screenshots editing")
struct SlotEditingTests {
    private static func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 400, height: 250))
        return session
    }

    @Test("[S15-AC5] slot and layout edits are single named undo steps; no-ops and the primary slot record nothing")
    func undo() throws {
        var session = try Self.session()
        var count = session.history.undoCount
        func expectStep(_ name: String) {
            #expect(session.history.undoCount == count + 1 && session.history.undoActionName == name)
            count = session.history.undoCount
        }
        let image = try Fixtures.solid(width: 40, height: 40)
        // Without a multi-slot arrangement there is nowhere to put a second screenshot.
        session.setSlotImage(image, at: 1)
        #expect(session.history.undoCount == count && session.contentSlots.count == 1)

        session.setCollage("cascade")
        expectStep("Change Screenshot Layout")
        #expect(session.collage?.id == "cascade" && session.contentSlots.count == 3)
        session.setCollage("cascade")
        session.setCollage("hologram")
        #expect(session.history.undoCount == count)

        session.setSlotImage(image, at: 0)  // the main screenshot
        session.setSlotImage(image, at: 9)  // no such screenshot
        #expect(session.history.undoCount == count)
        session.setSlotImage(image, at: 2)
        expectStep("Set Screenshot")
        try session.importSlotImage(data: Fixtures.encode(image, as: .png), at: 1)
        expectStep("Set Screenshot")
        #expect(session.document.slots.keys.sorted() == [1, 2] && session.document.slots[1]?.data != nil)
        #expect(throws: (any Error).self) { try session.importSlotImage(data: Data("nope".utf8), at: 1) }
        #expect(session.history.undoCount == count)

        session.removeScreenshot(at: 7)  // no such screenshot
        #expect(session.history.undoCount == count)
        session.removeScreenshot(at: 1)
        expectStep("Remove Screenshot")
        session.undo()
        #expect(session.document.slots[1] != nil && session.collage?.id == "cascade")

        session.clearContent()
        #expect(session.document.slots.isEmpty)
        session.undo()
        #expect(session.document.slots.count == 2)
        session.setCollage(nil)
        #expect(session.collage == nil && session.document.slotImages.isEmpty)
    }

    @Test("[S15-AC6] choosing a device removes the layout and vice versa; slot images are kept")
    func exclusive() throws {
        var session = try Self.session()
        session.setCollage("side-by-side")
        session.setSlotImage(try Fixtures.solid(width: 40, height: 40), at: 1)
        let count = session.history.undoCount
        session.setDevice("phone")
        #expect(session.history.undoCount == count + 1)
        #expect(session.project.collage == nil && session.collage == nil && session.device != nil)
        #expect(session.document.slots[1] != nil)
        session.setCollage("side-by-side")
        #expect(session.history.undoCount == count + 2)
        #expect(session.device == nil && session.document.slotImages.keys.sorted() == [1])
        session.setDevice("phone")
        session.setDeviceArrangement("pair")
        let pair = try #require(DeviceCatalog.bundled.arrangement("pair"))
        let other = try #require(pair.slots.indices.first { !pair.slots[$0].isPrimary })
        #expect(session.document.slotImages.keys.sorted() == [other])
    }

    @Test("[S15-AC10] adding screenshots fills the next slot and grows the layout, one undo step each")
    func addScreenshots() throws {
        var session = EditorSession()
        let image = try Fixtures.solid(width: 40, height: 40)
        #expect(session.addScreenshot(image) == .main)
        #expect(session.history.undoActionName == "Import Image" && session.collage == nil)
        #expect(session.addScreenshot(image, data: Data([1])) == .added(number: 1))
        #expect(session.collage?.id == "side-by-side" && session.history.undoActionName == "Add Screenshot")
        #expect(session.document.slots[1]?.data == Data([1]))
        #expect(session.addScreenshot(image) == .added(number: 2))
        #expect(session.collage?.id == "row")
        #expect(session.addScreenshot(image) == .added(number: 3))
        #expect(session.collage?.id == "grid" && session.document.slotImages.count == 3)
        let count = session.history.undoCount
        #expect(session.addScreenshot(image) == .full)
        #expect(session.history.undoCount == count)
        // Removing one shrinks the layout; adding again grows it back.
        session.removeScreenshot(at: 2)
        #expect(session.collage?.id == "row" && session.document.slots.count == 2)
        #expect(session.addScreenshot(image) == .added(number: 3) && session.collage?.id == "grid")
        // One undo removes the added screenshot and restores the previous layout.
        session.undo()
        #expect(session.collage?.id == "row" && session.document.slots[3] == nil)

        // A chosen layout is filled before it grows; a device gains devices.
        var device = EditorSession()
        device.setContent(image)
        device.setDevice("phone")
        #expect(device.addScreenshot(image) == .added(number: 1))
        #expect(device.device?.arrangement == "pair" && device.collage == nil)

        // Over a code snippet the image replaces the content, as before.
        var snippet = EditorSession()
        snippet.newCodeSnippet()
        #expect(snippet.addScreenshot(image, replacingName: "Capture Screenshot") == .main)
        #expect(snippet.document.snippet == nil && snippet.history.undoActionName == "Capture Screenshot")
        #expect(snippet.addScreenshot(image) == .added(number: 1))
    }

    @Test("[S15-AC13] adding a screenshot resets a layout preset that runs off the canvas, in the same undo step")
    func resetsBleed() throws {
        let image = try Fixtures.solid(width: 40, height: 40)
        for (transform, resets) in [
            (ContentTransform(x: 0.28, zoom: 115), true), (ContentTransform(zoom: 125), true),
            (ContentTransform(y: 0.24), true), (ContentTransform(x: -0.1, y: -0.08, zoom: 84), false),
            (ContentTransform(zoom: 90, tiltX: 16, tiltY: -24), false),
        ] {
            #expect(transform.bleedsOffCanvas == resets)
            var session = EditorSession()
            session.setContent(image)
            session.applyLayoutPreset(LayoutPreset(id: "preset", name: "Preset", transform: transform))
            session.addScreenshot(image)
            #expect(session.project.placement.transform.isIdentity == resets)
            #expect((session.project.placement.layoutPresetID == nil) == resets)
            session.undo()
            #expect(
                session.project.placement.transform == transform && session.collage == nil
                    && session.project.placement.layoutPresetID == "preset")
        }
    }

    @Test("[S15-AC11] any screenshot can be removed: later ones move up, the next becomes main, the layout shrinks")
    func removeAny() throws {
        var session = EditorSession()
        let images = try (0..<3).map { try Fixtures.solid(width: 40 + $0, height: 40) }
        for image in images { session.addScreenshot(image) }
        #expect(session.collage?.id == "row")
        session.setCrop(CropRect(x: 0, y: 0, width: 20, height: 20))
        // Removing the main screenshot promotes screenshot 2 and drops the crop that belonged to the old main.
        session.removeScreenshot(at: 0)
        #expect(session.document.content?.image.width == 41 && session.document.slots[1]?.image.width == 42)
        #expect(session.collage?.id == "side-by-side" && session.document.crop == nil)
        #expect(session.history.undoActionName == "Remove Screenshot")
        session.removeScreenshot(at: 1)
        #expect(session.collage == nil && session.document.slots.isEmpty)
        // The last image stays (Clear Content removes it).
        session.removeScreenshot(at: 0)
        #expect(session.document.content?.image.width == 41)
        session.undo()
        session.undo()
        #expect(session.document.content?.image.width == 40 && session.collage?.id == "row")
        #expect(session.document.crop != nil)

        // A device shrinks to the largest plain arrangement that fits.
        var device = EditorSession()
        device.setContent(images[0])
        device.setDevice("phone")
        device.addScreenshot(images[1])
        device.addScreenshot(images[2])
        #expect(device.device?.arrangement == "trio")
        device.removeScreenshot(at: 2)
        #expect(device.device?.arrangement == "pair")
        device.removeScreenshot(at: 0)
        #expect(device.device?.arrangement == "single" && device.device?.model == "phone")
    }

    @Test("[S15-AC12] dragging one screenshot onto another swaps them in one undo step")
    func swap() throws {
        var session = EditorSession()
        let images = try (0..<3).map { try Fixtures.solid(width: 40 + $0, height: 40) }
        for image in images { session.addScreenshot(image) }
        session.moveScreenshot(from: 2, to: 0)
        #expect(session.document.content?.image.width == 42 && session.document.slots[2]?.image.width == 40)
        #expect(session.history.undoActionName == "Move Screenshot")
        let count = session.history.undoCount
        session.moveScreenshot(from: 1, to: 1)
        session.moveScreenshot(from: 1, to: 5)
        #expect(session.history.undoCount == count)
        // The main slot can't be left empty.
        session.setCollage("grid")
        session.moveScreenshot(from: 3, to: 0)
        #expect(session.history.undoCount == count + 1 && session.document.content?.image.width == 42)
        session.moveScreenshot(from: 1, to: 3)
        #expect(session.document.slots[3]?.image.width == 41 && session.document.slots[1] == nil)
        session.undo()
        #expect(session.document.slots[1]?.image.width == 41)
    }

    @Test("[S15-AC14] the image trimmer cuts a solid border off a CGImage and leaves borderless images alone")
    func trimmer() throws {
        let framed = try Fixtures.draw(width: 120, height: 80) { context in
            context.setFillColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
            context.fill(CGRect(x: 20, y: 10, width: 70, height: 50))
        }
        let trimmed = try #require(ImageTrimmer.trimmed(framed))
        #expect(trimmed.width == 70 && trimmed.height == 50)
        #expect(ImageTrimmer.trimmed(try Fixtures.noise(width: 60, height: 40)) == nil)
    }

    @Test("[S15-AC7] slot images are saved with their original bytes and reopen in the same slots")
    func package() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        var session = try Self.session()
        session.setCollage("cascade")
        let jpeg = try Fixtures.encode(try Fixtures.solid(width: 60, height: 40, red: 0.9), as: .jpeg)
        try session.importSlotImage(data: jpeg, at: 1)
        session.setSlotImage(try Fixtures.solid(width: 30, height: 30, blue: 0.1), at: 2)
        let url = folder.file("Slots.sunshot")
        try DocumentPackage.write(session.document, to: url)

        let loaded = try DocumentPackage.read(from: url)
        #expect(loaded.document == session.document)
        #expect(loaded.document.slots[1]?.data == jpeg)
        #expect(loaded.document.media.isEmpty)
        let before = try #require(try session.render(scale: 1))
        let after = try #require(try Renderer.render(document: loaded.document, scale: 1))
        #expect(try ImageCodec.pngData(before) == ImageCodec.pngData(after))

        let json = try Data(contentsOf: url.appendingPathComponent(DocumentManifest.fileName))
        let manifest = try DocumentManifestCodec.decode(json).manifest
        #expect(manifest.slots?.map(\.number) == [1, 2])
        #expect(manifest.slots?.first?.pixelSize == PixelSize(width: 60, height: 40))

        // A missing slot file is refused, or shown as a placeholder of the recorded size when allowed.
        let slotPath = try #require(manifest.media.first { $0.id == manifest.slots?.first?.mediaID }?.path)
        try FileManager.default.removeItem(at: url.appendingPathComponent(slotPath))
        #expect(throws: DocumentFormatError.self) { try DocumentPackage.read(from: url) }
        let placeholder = try DocumentPackage.read(from: url, allowPlaceholders: true)
        #expect(placeholder.document.slots[1]?.pixelSize == PixelSize(width: 60, height: 40))
    }

    @Test("[S15-AC7] documents without slots save no slots key; a slot naming unknown media is refused")
    func manifest() throws {
        let plain = try DocumentPackage.contents(of: try Self.session().document).manifest
        #expect(plain.slots == nil)
        #expect(!String(decoding: try DocumentManifestCodec.encode(plain), as: UTF8.self).contains("\"slots\""))
        var broken = plain
        broken.slots = [SlotEntry(number: 1, mediaID: "ghost", pixelSize: PixelSize(width: 1, height: 1))]
        #expect(throws: DocumentFormatError.missingMedia(["ghost"])) {
            try DocumentManifestCodec.decode(DocumentManifestCodec.encode(broken))
        }
    }
}
