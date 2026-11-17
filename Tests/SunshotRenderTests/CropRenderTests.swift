import CoreGraphics
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

@Suite("Crop rendering and editing")
struct CropRenderTests {
    /// 1000×600: left half red, right half blue, with a green 100×100 block at (300, 200).
    private func content() throws -> CGImage {
        try Fixtures.draw(width: 1000, height: 600) { context in
            // CG draws bottom-up: flip so rects are in top-left image pixels.
            context.translateBy(x: 0, y: 600)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 500, height: 600))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 500, y: 0, width: 500, height: 600))
            context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 300, y: 200, width: 100, height: 100))
        }
    }

    private func session(crop: CropRect? = nil) throws -> EditorSession {
        let image = try content()
        var session = EditorSession(
            document: EditorDocument(project: .plain(padding: 0), content: ContentImage(image, data: Data([1, 2, 3]))))
        session.setCrop(crop)
        return session
    }

    @Test("[S10-AC5] the crop is rendered at 1× and 2×; the original image and bytes are kept")
    func rendersCrop() throws {
        let session = try session(crop: CropRect(x: 450, y: 150, width: 400, height: 300))
        let oneX = try #require(try session.render(scale: 1))
        #expect(oneX.width == 400 && oneX.height == 300)
        let pixels = try PixelBuffer(oneX)
        #expect(pixels.pixel(x: 10, y: 10) == [255, 0, 0, 255])  // source (460, 160): red half
        #expect(pixels.pixel(x: 390, y: 290) == [0, 0, 255, 255])  // source (840, 440): blue half
        let twoX = try #require(try session.render(scale: 2))
        #expect(twoX.width == 800 && twoX.height == 600)
        #expect(session.document.content?.pixelSize == PixelSize(width: 1000, height: 600))
        #expect(session.document.content?.data == Data([1, 2, 3]))
        #expect(session.canvasSize == PixelSize(width: 400, height: 300))
        #expect(session.document.contentPixelSize == PixelSize(width: 400, height: 300))
    }

    @Test("[S10-AC5] without a crop the render is identical to an uncropped document")
    func noCropUnchanged() throws {
        let image = try content()
        let plain = EditorDocument(project: .plain(), content: ContentImage(image))
        var withFullCrop = plain
        withFullCrop.crop = CropRect(full: PixelSize(width: 1000, height: 600))
        let reference = try PixelBuffer(try Renderer.render(project: .plain(), content: image))
        #expect(try PixelBuffer(try #require(try Renderer.render(document: plain))).bytes == reference.bytes)
        #expect(try PixelBuffer(try #require(try Renderer.render(document: withFullCrop))).bytes == reference.bytes)
        #expect(withFullCrop.effectiveCrop == nil)
    }

    @Test("[S10-AC6] Crop Image is one undo step; a full crop is no crop; repeats record nothing")
    func undo() throws {
        var session = try session()
        let crop = CropRect(x: 100, y: 50, width: 400, height: 300)
        session.setCrop(crop)
        #expect(session.crop == crop)
        #expect(session.history.undoActionName == EditorSession.cropActionName)
        let depth = session.history.undoCount
        session.setCrop(crop)
        #expect(session.history.undoCount == depth)
        session.undo()
        #expect(session.crop == nil)
        #expect(session.canvasSize == PixelSize(width: 1000, height: 600))
        session.redo()
        session.setCrop(CropRect(full: PixelSize(width: 1000, height: 600)))
        #expect(session.crop == nil && session.document.crop == nil)
        #expect(session.history.undoActionName == EditorSession.removeCropActionName)
        session.setCrop(crop)
        session.removeCrop()
        #expect(session.crop == nil)
    }

    @Test("[S10-AC6] replacing or clearing the content, or a new snippet, drops the crop")
    func contentChangesDropCrop() throws {
        let crop = CropRect(x: 100, y: 50, width: 400, height: 300)
        var replaced = try session(crop: crop)
        replaced.setContent(try Fixtures.solid(width: 50, height: 40))
        #expect(replaced.document.crop == nil)
        var cleared = try session(crop: crop)
        cleared.clearContent()
        #expect(cleared.document.crop == nil)
        var snippet = try session(crop: crop)
        snippet.newCodeSnippet()
        #expect(snippet.document.crop == nil && !snippet.canCrop)
        var captured = try session(crop: crop)
        captured.setCapturedContent(
            try Fixtures.solid(width: 20, height: 20), data: nil, actionName: EditorSession.captureScreenActionName)
        #expect(captured.document.crop == nil)
        #expect(captured.history.undoActionName == EditorSession.captureScreenActionName)
        var empty = EditorSession()
        empty.setCrop(crop)
        #expect(empty.document.crop == nil && !empty.history.canUndo)
    }

    @Test("[S10-AC9] annotations and redactions stay on the same image pixels after cropping")
    func annotationsFollowPixels() throws {
        var session = try session()
        let box = Annotation(
            kind: .rectangle, points: [AnnotationPoint(x: 300, y: 200), AnnotationPoint(x: 400, y: 280)],
            color: RGBAColor(red: 1, green: 1, blue: 0), lineWidth: 4, filled: true)
        session.addAnnotation(box)
        session.setCrop(CropRect(x: 200, y: 100, width: 400, height: 300))
        let pixels = try PixelBuffer(try #require(try session.render(scale: 1)))
        #expect(pixels.pixel(x: 150, y: 140) == [255, 255, 0, 255])  // inside the box at (100…200, 100…180)
        #expect(pixels.pixel(x: 50, y: 50) == [255, 0, 0, 255])  // outside: the red source pixel (250, 150)
        // The stored annotation keeps its uncropped coordinates.
        #expect(session.annotations.items.first?.points.first == AnnotationPoint(x: 300, y: 200))
        #expect(session.document.contentOrigin == AnnotationPoint(x: 200, y: 100))
        #expect(session.contentLongEdge == 400)
    }

    @Test("[S10-AC9] a redaction covers the same source pixels with or without a crop")
    func redactionFollowsPixels() throws {
        var session = try session()
        // Pixelate a region across the red / green boundary at (300, 200).
        session.addAnnotation(
            Annotation(
                kind: .redact, points: [AnnotationPoint(x: 280, y: 180), AnnotationPoint(x: 400, y: 300)],
                redaction: .pixelate))
        let uncropped = try PixelBuffer(try #require(try session.render(scale: 1)))
        session.setCrop(CropRect(x: 250, y: 150, width: 300, height: 250))
        let cropped = try PixelBuffer(try #require(try session.render(scale: 1)))
        for (x, y) in [(300, 200), (290, 190), (350, 250), (398, 298)] {
            #expect(cropped.pixel(x: x - 250, y: y - 150) == uncropped.pixel(x: x, y: y), "source (\(x), \(y))")
        }
        let boundary = cropped.pixel(x: 50, y: 50)
        #expect(boundary != [0, 255, 0, 255] && boundary != [255, 0, 0, 255])
        #expect(cropped.pixel(x: 10, y: 10) == [255, 0, 0, 255])  // source (260, 160): outside, untouched
    }

    @Test("[S10-AC9] layout, projection and thumbnails use the cropped size")
    func croppedSizeEverywhere() throws {
        var session = try session(crop: CropRect(x: 0, y: 0, width: 300, height: 200))
        #expect(session.contentProjection?.contentSize.width == 300)
        let scale = try #require(LayoutThumbnails.scale(for: session.document, maxSide: 100))
        #expect(abs(scale - 100.0 / 300.0) < 1e-9)
        session.clearContent()
        #expect(session.document.imageContentSize == nil)
        #expect(session.document.contentOrigin == AnnotationPoint(x: 0, y: 0))
    }

    @Test("[S10-AC10] a cropped document saves and reopens with its crop and original bytes")
    func savesCrop() throws {
        let image = try content()
        let png = try ImageCodec.pngData(image)
        var session = EditorSession()
        session.setContent(image, data: png)
        let crop = CropRect(x: 10, y: 20, width: 300, height: 200)
        session.setCrop(crop)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s10-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("cropped.sunshot")
        try DocumentPackage.write(session.document, to: url)
        let loaded = try DocumentPackage.read(from: url).document
        #expect(loaded.crop == crop)
        #expect(loaded.content?.data == png)
        #expect(loaded == session.document)
        // A crop beyond the image is clamped (or ignored) instead of failing.
        var outOfRange = loaded
        outOfRange.crop = CropRect(x: 900, y: 500, width: 500, height: 500)
        #expect(outOfRange.effectiveCrop == CropRect(x: 900, y: 500, width: 100, height: 100))
        outOfRange.crop = CropRect(x: 5000, y: 0, width: 5, height: 5)
        #expect(outOfRange.effectiveCrop == nil)
        #expect(try Renderer.render(document: outOfRange)?.width == 1000 + 2 * Int(SunshotDefaults.padding))
    }
}
