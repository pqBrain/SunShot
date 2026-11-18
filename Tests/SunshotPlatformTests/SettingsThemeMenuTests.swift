import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Settings, themes and menus", .serialized)
struct SettingsThemeMenuTests {
    // MARK: Settings

    @Test("[S7-AC12] settings persist across relaunch under the app.sunshot. prefix")
    func settingsPersist() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let folder = fixture.folder.file("Exports")
        fixture.controller.settings = AppSettings(
            appearance: .dark, filenameTemplate: "{DATE}", exportFolder: folder, confirmReset: false)
        let relaunched = fixture.relaunch()
        #expect(relaunched.settings.appearance == .dark && relaunched.settings.filenameTemplate == "{DATE}")
        #expect(relaunched.settings.exportFolder?.path == folder.path && !relaunched.settings.confirmReset)
        #expect(fixture.defaults.string(forKey: "app.sunshot.appearance") == "dark")
        relaunched.settings.exportFolder = nil
        #expect(fixture.relaunch().settings.exportFolder == nil)
        fixture.controller.settings.appearance = .system
    }

    @Test("[S7-AC13] appearance applies the app-wide override (System follows the OS) and never changes exports")
    func appearance() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let app = NSApplication.shared
        await controller.model.importData(try TestImages.png())
        let exported = try await controller.model.exportData()
        controller.settings.appearance = .dark
        #expect(app.appearance?.name == .darkAqua)
        #expect(try await controller.model.exportData() == exported)
        controller.settings.appearance = .light
        #expect(app.appearance?.name == .aqua)
        controller.settings.appearance = .system
        #expect(app.appearance == nil)
        #expect(AppearanceSetting.allCases.map(UIStrings.appearanceName) == ["System", "Light", "Dark"])
    }

    @Test("[S7-AC14] the saved export name uses the Settings template; blank falls back to the default")
    func exportNameUsesSetting() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png(width: 1000, height: 600))
        controller.model.perform { $0.setExportScale(.x1) }
        controller.settings.filenameTemplate = "{TEMPLATE}-{WIDTH}x{HEIGHT}"
        #expect(controller.model.suggestedExportName() == "screenshot-1128x728.png")
        controller.settings.filenameTemplate = ""
        #expect(controller.model.suggestedExportName().hasPrefix("screenshot_1x_sunshot_"))
        controller.settings.filenameTemplate = SunshotDefaults.filenameTemplate
        #expect(fixture.relaunch().model.filenameTemplate == SunshotDefaults.filenameTemplate)
    }

    @Test("[S7-AC15] default export folder: direct write with \" 2\" on collisions; missing folder → panel + notice")
    func exportFolder() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        let date = Date(timeIntervalSince1970: 0)
        guard case .panel(_, nil) = controller.exportDestination(now: date) else {
            Issue.record("no folder set must show the panel without a notice")
            return
        }
        let folder = fixture.folder.file("Pictures-Sunshot")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        controller.settings.exportFolder = folder
        controller.settings.filenameTemplate = "shot"
        #expect(controller.exportDestination(now: date) == .file(folder.appendingPathComponent("shot.png")))
        await controller.model.export(to: folder.appendingPathComponent("shot.png"))
        #expect(controller.exportDestination(now: date) == .file(folder.appendingPathComponent("shot 2.png")))
        try FileManager.default.removeItem(at: folder)
        guard case .panel(let directory, let notice) = controller.exportDestination(now: date) else {
            Issue.record("missing folder must fall back to the panel")
            return
        }
        #expect(directory?.lastPathComponent == "Pictures" && notice == UIStrings.exportFolderUnavailable)
        controller.settings.exportFolder = nil
        #expect(controller.exportDestination(now: date) == .panel(directory: directory, notice: nil))
    }

    // MARK: Start Over

    @Test("[S7-AC8] [S7-AC16] Start Over without confirmation resets at once; settings survive; default is a no-op")
    func startOver() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        controller.settings = AppSettings(appearance: .system, filenameTemplate: "{DATE}", confirmReset: false)
        #expect(!controller.isEnabled(.startOver) && !controller.startOverNeedsConfirmation)
        await controller.model.importData(try TestImages.png())
        controller.model.perform { $0.setCornerStyle(.sharp) }
        #expect(controller.isEnabled(.startOver) && !controller.startOverNeedsConfirmation)
        controller.startOver()
        #expect(controller.model.session.document == EditorSession.defaultDocument)
        #expect(controller.model.undoTitle == "Undo Start Over")
        let undoCount = controller.model.session.history.undoCount
        controller.startOver()
        #expect(controller.model.session.history.undoCount == undoCount)
        #expect(controller.settings.filenameTemplate == "{DATE}" && !controller.settings.confirmReset)
        await controller.newDocument()
        #expect(controller.model.project == Project() && controller.settings.filenameTemplate == "{DATE}")
        controller.settings.confirmReset = true
        await controller.model.importData(try TestImages.png())
        #expect(controller.startOverNeedsConfirmation)
        #expect(UIStrings.startOverTitle == "Start over?" && UIStrings.startOverButton == "Start Over")
    }

    // MARK: Menus

    @Test("[S7-AC17] the menu bar lists every required item with its shortcut and no clashes")
    func menuCatalog() {
        let expected: [(MenuCommand, String, String?)] = [
            (.new, "New", "⌘N"), (.open, "Open…", "⌘O"), (.openRecent, "Open Recent", nil), (.close, "Close", "⌘W"),
            (.save, "Save", "⌘S"), (.saveAs, "Save As…", "⌥⇧⌘S"), (.exportImage, "Export Image…", "⇧⌘E"),
            (.startOver, "Start Over", nil), (.undo, "Undo", "⌘Z"), (.redo, "Redo", "⇧⌘Z"), (.cut, "Cut", "⌘X"),
            (.copy, "Copy", "⌘C"), (.paste, "Paste", "⌘V"), (.selectAll, "Select All", "⌘A"),
            (.clearContent, "Clear Content", "⌘⌫"), (.toggleInspector, "Show/Hide Inspector", "⌥⌘E"),
            (.enterFullScreen, "Enter Full Screen", "⌃⌘F"), (.minimize, "Minimize", "⌘M"), (.zoom, "Zoom", nil),
            (.settings, "Settings…", "⌘,"),
        ]
        for (command, title, shortcut) in expected {
            #expect(MenuCatalog.title(command) == title)
            #expect(MenuCatalog.shortcut(command)?.description == shortcut, "\(command)")
        }
        #expect(MenuCatalog.menus.map(\.title) == ["Sunshot", "File", "Edit", "View", "Window", "Help"])
        #expect(MenuCatalog.clashes.isEmpty)
        #expect(Set(MenuCatalog.items.map(\.command)) == Set(MenuCommand.allCases))
        // Every shortcut defined by S1–S4 appears in a menu.
        let earlier = ["⌘O", "⌘V", "⌘C", "⇧⌘E", "⌘Z", "⇧⌘Z", "⌥⌘E", "⌘⌫"]
        let listed = Set(MenuCatalog.items.compactMap { $0.shortcut?.description })
        #expect(earlier.allSatisfy(listed.contains))
        #expect(MenuCatalog.item(.help)?.isSystem == true && MenuCatalog.item(.save)?.isSystem == false)
    }

    @Test("[S7-AC18] menu enablement: content actions off when empty, on with content; Save As always on")
    func menuEnablement() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let contentOnly: [MenuCommand] = [.exportImage, .copy, .clearContent, .startOver, .save]
        #expect(contentOnly.allSatisfy { !controller.isEnabled($0) })
        #expect([.saveAs, .openRecent, .open, .new].allSatisfy { controller.isEnabled($0) })
        #expect(!controller.isEnabled(.undo) && !controller.isEnabled(.redo))
        await controller.model.importData(try TestImages.png())
        #expect(contentOnly.allSatisfy { controller.isEnabled($0) })
        controller.model.perform { $0.setCornerStyle(.sharp) }
        #expect(controller.menuTitle(.undo) == "Undo Change Corner Style" && controller.isEnabled(.undo))
        await controller.model.undo()
        #expect(controller.menuTitle(.redo) == "Redo Change Corner Style" && controller.isEnabled(.redo))
        #expect(controller.menuTitle(.toggleInspector) == "Hide Inspector")
        controller.model.showsInspector = false
        #expect(controller.menuTitle(.toggleInspector) == "Show Inspector")
        #expect(controller.menuTitle(.exportImage) == "Export Image…")
    }

    @Test("[S7-AC22] settings and dialogs carry spoken labels")
    func accessibilityLabels() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        let settingsLabels = [
            UIStrings.appearance, UIStrings.filenameFormat, UIStrings.exportFolder, UIStrings.confirmReset,
            UIStrings.defaultTemplate, UIStrings.choose, UIStrings.clear,
        ]
        #expect(settingsLabels.allSatisfy { !$0.isEmpty } && Set(settingsLabels).count == settingsLabels.count)
        #expect(AppearanceSetting.allCases.map(UIStrings.appearanceName).allSatisfy { !$0.isEmpty })
        let dialogButtons = [UIStrings.save, UIStrings.dontSave, UIStrings.cancel, UIStrings.startOverButton]
        #expect(dialogButtons.allSatisfy { !$0.isEmpty } && Set(dialogButtons).count == dialogButtons.count)
        #expect(UIStrings.saveChangesTitle(UIStrings.untitled) == "Save changes to Untitled?")
    }
}
