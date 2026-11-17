import AppKit
import Foundation
import ImageIO
import SunshotCore
import SunshotRender
import Testing
import UniformTypeIdentifiers

@testable import SunshotPlatform

private func screenshotPNG(width: Int, height: Int, comment: String? = "Screenshot") throws -> Data {
    let image = try TestImages.solid(width: width, height: height)
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let comment { properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: comment] }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

@MainActor
@Suite("Styling macOS screenshots on the clipboard", .serialized)
struct SystemScreenshotStylerTests {
    @Test("[S16-AC11] a macOS screenshot copied to the clipboard is replaced with the default style, frame None")
    func stylesSystemScreenshot() async throws {
        var project = Project()
        project.padding = 50
        project.frame.kind = .macWindow
        let style = QuickStyle(project: project)
        try await withPrivatePasteboard { pasteboard in
            let styler = SystemScreenshotStyler(pasteboard: pasteboard) { style }
            var styledCount = 0
            styler.onStyled = { styledCount += 1 }
            #expect(!(await styler.check()), "nothing new on the clipboard")

            PasteboardIO.writePNG(try screenshotPNG(width: 200, height: 100), to: pasteboard)
            #expect(await styler.check())
            let image = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
            #expect(image.width == 300 && image.height == 200, "padding only, no title bar")
            #expect(styledCount == 1)
            #expect(!(await styler.check()), "its own copy is not styled again")
        }
    }

    @Test("[S16-AC11] other images, files and mixed clipboards are left alone; the setting is saved")
    func leavesOtherClipboardsAlone() async throws {
        let style = QuickStyle(project: Project())
        try await withPrivatePasteboard { pasteboard in
            let styler = SystemScreenshotStyler(pasteboard: pasteboard) { style }
            let plain = try screenshotPNG(width: 60, height: 40, comment: nil)
            PasteboardIO.writePNG(plain, to: pasteboard)
            #expect(!(await styler.check()))
            #expect(pasteboard.data(forType: .png) == plain)

            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setData(try screenshotPNG(width: 60, height: 40), forType: .png)
            item.setString("<img>", forType: .html)
            pasteboard.writeObjects([item])
            #expect(!(await styler.check()))
        }
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let store = SettingsStore(defaults: fixture.defaults)
        var settings = store.load()
        #expect(settings.styleSystemScreenshots)
        settings.styleSystemScreenshots = false
        store.save(settings)
        #expect(!store.load().styleSystemScreenshots)
    }

    @Test("[S16-AC13] pasting a styled copy into the studio uses the original capture, so the backdrop isn't doubled")
    func pasteUsesOriginal() async throws {
        var project = Project()
        project.padding = 50
        project.frame.kind = .macWindow
        let style = QuickStyle(project: project)
        try await withPrivatePasteboard { pasteboard in
            let styler = SystemScreenshotStyler(pasteboard: pasteboard) { style }
            PasteboardIO.writePNG(try screenshotPNG(width: 200, height: 100), to: pasteboard)
            #expect(await styler.check())
            let model = EditorModel()
            model.perform { $0.setFrameKind(.macWindow) }
            await model.paste(from: pasteboard)
            let content = try #require(model.session.document.content)
            #expect(content.image.width == 200 && content.image.height == 100)
            #expect(model.project.frame.kind == .none, "still a macOS screenshot: no frame")

            // A styled shortcut capture pastes as the captured pixels too.
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            fixture.controller.model.capture.screen = FakeScreen(image: try TestImages.solid(width: 300, height: 200))
            #expect(
                await fixture.controller.deliverCapture(.window(3), to: .styledClipboard, pasteboard: pasteboard))
            let pasted = try ImageCodec.decode(try #require(PasteboardIO.imageData(from: pasteboard)))
            #expect(pasted.width == 300 && pasted.height == 200)
            let styled = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
            #expect(styled.width > 300, "other apps get the styled image")
        }
    }

    @Test("[S16-AC1] a raw shortcut copy saved before styled copies existed becomes the styled copy once")
    func migratesRawShortcutCopy() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("clipboard", forKey: "app.sunshot.captureDestination")
        let store = SettingsStore(defaults: fixture.defaults)
        var settings = store.load()
        #expect(settings.globalCaptureDestination == .styledClipboard)
        // Chosen again after the upgrade, the raw copy is kept.
        settings.globalCaptureDestination = .clipboard
        store.save(settings)
        #expect(store.load().globalCaptureDestination == .clipboard)
    }
}
