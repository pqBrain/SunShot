import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Menu bar quick capture, default style and the studio", .serialized)
struct QuickCaptureTests {
    @Test("[S16-AC1] menu bar icon, annotate-on-open and the shortcut choice are saved in Settings")
    func settingsPersistence() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let store = SettingsStore(defaults: fixture.defaults)
        var settings = store.load()
        #expect(settings.showsMenuBarIcon && settings.annotateOnOpen && settings.captureHotkeyEnabled)
        #expect(settings.globalCaptureDestination == .styledClipboard)
        settings.showsMenuBarIcon = false
        settings.annotateOnOpen = false
        store.save(settings)
        #expect(!store.load().showsMenuBarIcon && !store.load().annotateOnOpen)
    }

    @Test("[S16-AC2] a styled shortcut capture copies the default style's render; the document is untouched")
    func styledCopy() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let model = controller.model
        model.capture.screen = FakeScreen(image: try TestImages.solid(width: 300, height: 200))
        model.session.setContent(try TestImages.solid(width: 50, height: 50))
        model.perform { $0.setPadding(64) }
        controller.saveQuickStyle()
        let undoCount = model.session.history.undoCount
        try await withPrivatePasteboard { pasteboard in
            let copied = await controller.deliverCapture(
                .area(LayoutRect(x: 0, y: 0, width: 150, height: 100), displayID: 1), to: .styledClipboard,
                pasteboard: pasteboard)
            #expect(copied)
            let image = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
            let expected = try QuickStyleRenderer.render(
                try TestImages.solid(width: 300, height: 200), style: controller.quickStyle)
            #expect(image.width == expected.width && image.height == expected.height)
            #expect(image.width > 300 && image.height > 200)
            // Raw clipboard copies the capture as is; windows copy like areas.
            #expect(await controller.deliverCapture(.window(7), to: .clipboard, pasteboard: pasteboard))
            let raw = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
            #expect(raw.width == 300 && raw.height == 200)
        }
        #expect(model.session.history.undoCount == undoCount)
        #expect(!model.annotate.isActive)
    }

    @Test("[S16-AC2] a failed or refused styled capture copies nothing")
    func styledCopyFailure() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let model = fixture.controller.model
        model.capture.screen = FakeScreen(error: .failed("Gone."))
        await withPrivatePasteboard { pasteboard in
            #expect(
                !(await fixture.controller.deliverCapture(.window(1), to: .styledClipboard, pasteboard: pasteboard)))
            #expect(pasteboard.data(forType: .png) == nil)
            #expect(model.alert?.message == "Gone.")
        }
    }

    @Test("[S16-AC3] Save as Default Style persists, styles new documents, survives relaunch and can be cleared")
    func defaultStyle() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        #expect(controller.quickStyle == nil)
        #expect(controller.effectiveQuickStyle.project == controller.defaultTemplateDocument.project)
        controller.model.session.setContent(try TestImages.solid(width: 80, height: 60))
        controller.model.perform { $0.setPadding(77) }
        controller.saveQuickStyle(now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(controller.model.notice == DocumentController.defaultStyleSavedNotice)
        #expect(controller.quickStyle?.project.padding == 77)
        #expect(controller.defaultTemplateDocument.project.padding == 77)
        #expect(controller.defaultTemplateDocument.content == nil)
        await controller.newDocument()
        #expect(controller.model.project.padding == 77 && !controller.model.hasContent)

        let relaunched = fixture.relaunch()
        #expect(relaunched.quickStyle?.project.padding == 77)
        relaunched.clearQuickStyle()
        #expect(relaunched.quickStyle == nil)
        #expect(fixture.relaunch().quickStyle == nil)
    }

    @Test("[S16-AC3] an unreadable default style file is ignored")
    func corruptDefaultStyle() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let file = fixture.controller.locations.quickStyle
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: file)
        #expect(fixture.relaunch().quickStyle == nil)
        #expect(QuickStyleStore(file: file).load() == nil)
    }

    @Test("[S16-AC5] a capture opened in the studio starts in Annotate mode unless Settings turn it off")
    func annotateOnOpen() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let model = controller.model
        model.capture.screen = FakeScreen(image: try TestImages.solid(width: 300, height: 200))
        let copied = await controller.deliverCapture(
            .area(LayoutRect(x: 0, y: 0, width: 150, height: 100), displayID: 1), to: .editor)
        #expect(!copied)
        #expect(model.hasContent && model.annotate.isActive)

        model.setAnnotateMode(false)
        controller.settings.annotateOnOpen = false
        await controller.deliverCapture(.window(3), to: .editor)
        #expect(!model.annotate.isActive)
    }

    @Test("[S16-AC4] the hover picker gets on-screen windows front to back, without Sunshot's own")
    func pickableWindows() async throws {
        let model = EditorModel()
        let frame = LayoutRect(x: 0, y: 0, width: 500, height: 400)
        model.capture.screen = FakeScreen(windowList: [
            CapturableWindow(id: 9, title: "Top", appName: "Notes", width: 500, height: 400, frame: frame),
            CapturableWindow(id: 3, title: "Under", appName: "Mail", width: 500, height: 400, frame: frame),
            CapturableWindow(id: 4, title: "Hidden", appName: "Mail", width: 500, height: 400),
        ])
        #expect(await model.pickableWindows()?.map(\.id) == [9, 3])
        model.capture.screen = FakeScreen(granted: false)
        #expect(await model.pickableWindows() == nil)
        #expect(model.capture.showsPermissionHelp)
    }

    @Test("[S16-AC6] Screenshot ⇄ Code keeps both sides; New Code Snippet keeps the image to come back to")
    func contentKind() async throws {
        let model = EditorModel()
        await model.importData(try ImageCodec.pngData(try TestImages.solid(width: 120, height: 80)))
        let image = model.session.document.content
        #expect(model.contentKind == .screenshot)
        await model.setContentKind(.code).value
        #expect(model.contentKind == .code && model.snippet == CodeSnippet())
        await model.perform { $0.setCode("print(1)") }.value
        await model.setContentKind(.screenshot).value
        #expect(model.session.document.content == image && model.snippet == nil)
        await model.setContentKind(.code).value
        #expect(model.snippet?.code == "print(1)")
        await model.setContentKind(.screenshot).value
        // New Code Snippet (menu) starts a fresh snippet, and the image still comes back.
        await model.newCodeSnippet().value
        #expect(model.snippet == CodeSnippet())
        await model.setContentKind(.screenshot).value
        #expect(model.session.document.content == image)
        // Switching to the side already shown changes nothing.
        let count = model.session.history.undoCount
        await model.setContentKind(.screenshot).value
        #expect(model.session.history.undoCount == count)
    }
}
