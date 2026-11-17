import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Devices and templates in the editor", .serialized)
struct DeviceTemplateModelTests {
    @Test("[S12-AC14] a matching image is offered its device; Use is one undo step; the setting persists")
    func suggestionInEditor() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let model = controller.model
        #expect(controller.settings.suggestDevice)
        #expect(model.deviceSuggestion(enabled: true) == nil)
        await model.importData(try TestImages.png(width: 1179, height: 2556))
        let suggestion = try #require(model.deviceSuggestion(enabled: true))
        #expect(suggestion.model.id == "phone" && !suggestion.landscape)
        #expect(UIStrings.deviceSuggestion(suggestion) == "This image fits a Phone")
        #expect(model.deviceSuggestion(enabled: false) == nil)
        await model.applyDeviceSuggestion(suggestion).value
        #expect(model.device == DeviceSelection(model: "phone") && model.undoTitle == "Undo Change Device")
        #expect(model.deviceSuggestion(enabled: true) == nil)
        #expect(model.recommendedMediaSize == PixelSize(width: 1080, height: 2340))
        // No suggestion for shapes no device has, or for snippets.
        await model.importData(try TestImages.png(width: 500, height: 500))
        await model.perform { $0.setDevice(nil) }.value
        #expect(model.deviceSuggestion(enabled: true) == nil)
        model.newCodeSnippet()
        #expect(model.deviceSuggestion(enabled: true) == nil)
        // The setting persists.
        controller.settings.suggestDevice = false
        let relaunched = fixture.relaunch()
        #expect(!relaunched.settings.suggestDevice)
        #expect(SettingsStore(defaults: fixture.defaults).load().suggestDevice == false)
    }

    @Test("[S12-AC12] the inspector's device actions, options and tiles")
    func inspectorActions() async throws {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 400, height: 250))
        #expect(model.deviceModels.map(\.id) == ["phone", "tablet", "laptop", "desktop"])
        #expect(model.deviceFinishes.count == 4 && model.deviceArrangements.isEmpty && !model.canTurnDevice)
        await model.perform { _ in }.value
        model.setDevice("tablet")
        #expect(model.canTurnDevice && model.deviceArrangements.map(\.id).contains("tablet-phone"))
        model.setDeviceLandscape(true)
        #expect(model.recommendedMediaSize == PixelSize(width: 2752, height: 2064))
        model.setDeviceFinish("sage")
        model.setDeviceArrangement("pair")
        #expect(model.device == DeviceSelection(model: "tablet", finish: "sage", landscape: true, arrangement: "pair"))
        model.setDeviceArrangement("laptop-phone")
        #expect(model.recommendedMediaSize == PixelSize(width: 2560, height: 1600) && !model.canTurnDevice)
        let phone = try #require(model.deviceModels.first)
        let tile = try #require(model.deviceThumbnail(phone))
        #expect(model.deviceThumbnail(phone) === tile)
        #expect(UIStrings.deviceOption("Phone", selected: true) == "Device: Phone, selected")
        #expect(UIStrings.finishOption("Sand", selected: false) == "Finish: Sand")
        #expect(UIStrings.recommendedMedia(PixelSize(width: 1080, height: 2340)) == "Best with 1080 × 2340 px")
    }

    @Test("[S12-AC21] Annotate is unavailable on a device mockup")
    func annotateOff() async throws {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 400, height: 250))
        #expect(model.canAnnotate)
        model.setDevice("laptop")
        #expect(!model.canAnnotate)
        model.setAnnotateMode(true)
        #expect(!model.annotate.isActive)
    }

    @Test("[S12-AC17] the gallery renders a live preview per template and applies one in a single step")
    func gallery() async throws {
        let model = EditorModel()
        let templates = model.templates.templates
        #expect(templates.count >= 12)
        model.showTemplateGallery()
        #expect(model.templates.isPresented)
        await model.templates.thumbnailTask?.value
        #expect(Set(model.templates.thumbnails.keys) == Set(templates.map(\.id)))
        // Same content again: nothing re-renders.
        #expect(model.scheduleTemplateThumbnails() == nil)
        await model.importData(try TestImages.png(width: 400, height: 250))
        await model.scheduleTemplateThumbnails()?.value
        let card = try #require(model.templates.thumbnails["open-laptop"])
        let template = try #require(templates.first { $0.id == "open-laptop" })
        let expected = try #require(try TemplateThumbnails.render(template, document: model.session.document))
        #expect(card.width == expected.width && card.height == expected.height)
        #expect(model.isCurrentTemplate(templates[0]) && !model.isCurrentTemplate(template))
        await model.applyTemplate(template).value
        #expect(!model.templates.isPresented && model.isCurrentTemplate(template))
        #expect(model.undoTitle == "Undo Apply Template Open Laptop")
        #expect(UIStrings.templateOption(template, current: true).hasPrefix("Template: Open Laptop, "))
    }

    @Test("[S12-AC19] the default template drives New, Start Over and launch; unknown values fall back")
    func defaultTemplate() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        #expect(controller.settings.defaultTemplate == "Screenshot")
        #expect(controller.defaultTemplateID == "screenshot")
        #expect(controller.defaultTemplateDocument == EditorSession.defaultDocument)
        #expect(!controller.isEnabled(.startOver))
        controller.defaultTemplateID = "pocket-spotlight"
        #expect(controller.settings.defaultTemplate == "pocket-spotlight")
        let start = controller.defaultTemplateDocument
        #expect(start.project.frame.device?.model == "phone")
        // The current (plain) document differs from the template: Start Over is offered.
        #expect(controller.isEnabled(.startOver))
        await controller.model.importData(try TestImages.png())
        #expect(controller.startOverNeedsConfirmation)
        controller.startOver()
        #expect(controller.model.session.document == start && !controller.isEnabled(.startOver))
        await controller.newDocument()
        #expect(controller.model.session.document == start)
        // Launch opens the default template; the setting persists.
        let relaunched = fixture.relaunch()
        #expect(relaunched.settings.defaultTemplate == "pocket-spotlight")
        #expect(relaunched.model.session.document == start && !relaunched.isDirty)
        controller.settings.defaultTemplate = "retired-template"
        #expect(controller.defaultTemplateID == "screenshot")
        #expect(controller.defaultTemplateDocument == EditorSession.defaultDocument)
    }

    @Test("[S12-AC22] Templates… is in the File menu with ⇧⌘T and no clashes")
    func menu() {
        #expect(MenuCatalog.title(.templateGallery) == "Templates…")
        #expect(MenuCatalog.shortcut(.templateGallery)?.description == "⇧⌘T")
        #expect(MenuCatalog.clashes.isEmpty)
        #expect(
            MenuCatalog.menus.first { $0.title == "File" }?.items.contains { $0.command == .templateGallery } == true)
    }

    @Test("[S12-AC17] a catalog that fails to load leaves an empty gallery")
    func failedLibrary() {
        struct Broken: Error {}
        let library = TemplateLibrary(load: { throw Broken() })
        #expect(library.catalog == nil && library.templates.isEmpty && library.template(matching: "x") == nil)
        let state = TemplateGalleryState(library: library)
        #expect(state.templates.isEmpty)
    }
}
