import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

/// S7: the slimmer toolbar (commands reachable from the menu bar), the sidebar picker and the auto backdrop.
@MainActor
@Suite("Simpler editor", .serialized)
struct SimplerEditorTests {
    @Test("[S7-AC23] Clear Content, Start Over and Copy stay in the menu bar with their shortcuts")
    func removedToolbarCommandsStayInMenus() async throws {
        #expect(MenuCatalog.title(.clearContent) == "Clear Content")
        #expect(MenuCatalog.shortcut(.clearContent)?.description == "⌘⌫")
        #expect(MenuCatalog.title(.copy) == "Copy")
        #expect(MenuCatalog.shortcut(.copy)?.description == "⌘C")
        #expect(MenuCatalog.title(.startOver) == "Start Over")
        #expect(MenuCatalog.title(.templateGallery).hasPrefix("Templates"))
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        for command in [MenuCommand.copy, .clearContent, .startOver] {
            #expect(!controller.isEnabled(command), "\(command)")
        }
        await controller.model.importData(try TestImages.png())
        for command in [MenuCommand.copy, .clearContent, .startOver] {
            #expect(controller.isEnabled(command), "\(command)")
        }
        #expect(UIStrings.copyPNG == "Copy PNG" && UIStrings.exportOptionsMenu == "Export Options…")
    }

    @Test("[S7-AC24] the sidebar picker offers Layouts, Templates and Themes in that order")
    func sidebarPanes() {
        #expect(SidebarPane.allCases.map(\.title) == ["Layouts", "Templates", "Themes"])
        #expect(SidebarPane.allCases.map(\.id) == ["layouts", "templates", "themes"])
        #expect(UIStrings.layoutsEmpty == "Add an image to try layouts.")
        #expect(UIStrings.themeRow("Ocean", applied: true) == "Theme: Ocean, applied")
        #expect(UIStrings.themeRow("Ocean", applied: false) == "Theme: Ocean")
        #expect(UIStrings.saveCurrentTheme == "Save current style as theme")
    }

    @Test("[S7-AC25] the setting (on by default) styles the first image's backdrop; off keeps it; it persists")
    func autoBackdropSetting() async throws {
        #expect(AppSettings().autoBackdropOnImport)
        #expect(!EditorModel().autoBackdropOnImport)
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let model = controller.model
        #expect(model.autoBackdropOnImport)
        await model.importData(try TestImages.png(width: 60, height: 40, red: 0.8))
        guard case .image(.wallpaper) = model.project.backdrop else {
            Issue.record("expected an auto background, got \(model.project.backdrop)")
            return
        }
        #expect(model.undoTitle == "Undo Import Image")
        await model.undo()
        #expect(!model.hasContent && model.project.hasUntouchedBackdrop)

        controller.settings.autoBackdropOnImport = false
        #expect(!model.autoBackdropOnImport)
        await model.importData(try TestImages.png(width: 60, height: 40, red: 0.8))
        #expect(model.project.hasUntouchedBackdrop)
        let relaunched = fixture.relaunch()
        #expect(!relaunched.settings.autoBackdropOnImport && !relaunched.model.autoBackdropOnImport)
        #expect(SettingsStore(defaults: fixture.defaults).load().autoBackdropOnImport == false)
    }
}
