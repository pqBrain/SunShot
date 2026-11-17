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

    // MARK: Themes

    @Test("[S7-AC9] Save Theme writes Themes/ocean.json and the header shows the name; bad names are refused")
    func saveTheme() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        controller.model.perform { $0.setBackdropColor(.black) }
        #expect(controller.themeHeaderTitle == "No Theme")
        let ocean = try controller.saveTheme(named: " Ocean ")
        let file = fixture.folder.file("Themes/ocean.json")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(controller.themeHeaderTitle == "Ocean" && ocean.name == "Ocean")
        #expect(throws: ThemeName.Problem.duplicate(existingID: ocean.id)) { try controller.saveTheme(named: "OCEAN") }
        #expect(throws: ThemeName.Problem.empty) { try controller.saveTheme(named: "  ") }
        controller.model.perform { $0.setCornerRadius(99) }
        #expect(controller.themeHeaderTitle == "Ocean (modified)")
        let replaced = try controller.saveTheme(named: "ocean", replacing: true)
        #expect(replaced.id == ocean.id && controller.themes.count == 1)
        #expect(controller.themeHeaderTitle == "ocean")
        let odd = try controller.saveTheme(named: "A/B: Night")
        #expect(FileManager.default.fileExists(atPath: fixture.folder.file("Themes/ab night.json").path))
        #expect(controller.themes.contains { $0.id == odd.id && $0.name == "A/B: Night" })
    }

    @Test("[S7-AC10] applying a theme from the menu is one undo step; undo restores the previous header")
    func applyTheme() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        controller.model.perform { $0.setBackdropColor(.white) }
        let ocean = try controller.saveTheme(named: "Ocean")
        controller.model.perform { $0.setCornerStyle(.sharp) }
        let paper = try controller.saveTheme(named: "Paper")
        controller.applyTheme(ocean)
        #expect(controller.model.undoTitle == "Undo Apply Theme Ocean" && controller.themeHeaderTitle == "Ocean")
        controller.applyTheme(paper)
        #expect(controller.themeHeaderTitle == "Paper" && controller.model.project.border.style == .sharp)
        await controller.model.undo()
        #expect(controller.themeHeaderTitle == "Ocean" && controller.model.project.border.style != .sharp)
    }

    @Test("[S7-AC11] rename, duplicate, delete; deleting the applied theme keeps the style; corrupt files skipped")
    func manageThemes() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        let ocean = try controller.saveTheme(named: "Ocean")
        try controller.renameTheme(id: ocean.id, to: "Sea")
        #expect(controller.themes.map(\.name) == ["Sea"] && controller.themeHeaderTitle == "Sea")
        #expect(FileManager.default.fileExists(atPath: fixture.folder.file("Themes/sea.json").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.file("Themes/ocean.json").path))
        let copy = try #require(try controller.duplicateTheme(id: ocean.id))
        #expect(copy.name == "Sea copy" && controller.themes.count == 2)
        #expect(throws: ThemeName.Problem.duplicate(existingID: copy.id)) {
            try controller.renameTheme(id: ocean.id, to: "sea COPY")
        }
        try Data("{broken".utf8).write(to: fixture.folder.file("Themes/broken.json"))
        try Data(#"{"schemaVersion":1,"id":"x","name":"Bad","style":{"border":"nope"}}"#.utf8)
            .write(to: fixture.folder.file("Themes/bad.json"))
        controller.reloadThemes()
        #expect(controller.themes.map(\.name) == ["Sea", "Sea copy"])
        let style = controller.model.project
        try controller.deleteTheme(id: ocean.id)
        #expect(controller.themes.map(\.name) == ["Sea copy"])
        #expect(controller.model.project == style && controller.themeHeaderTitle == "No Theme")
        #expect(try controller.duplicateTheme(id: "missing") == nil)
    }

    // MARK: Menus

    @Test("[S7-AC17] the menu bar lists every required item with its shortcut and no clashes")
    func menuCatalog() {
        let expected: [(MenuCommand, String, String?)] = [
            (.new, "New", "⌘N"), (.open, "Open…", "⌘O"), (.openRecent, "Open Recent", nil), (.close, "Close", "⌘W"),
            (.save, "Save", "⌘S"), (.saveAs, "Save As…", "⇧⌘S"), (.exportImage, "Export Image…", "⇧⌘E"),
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

    @Test("[S7-AC22] settings, theme header and dialogs carry spoken labels; the theme reads \"Theme: Ocean\"")
    func accessibilityLabels() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        _ = try controller.saveTheme(named: "Ocean")
        #expect(UIStrings.themeAccessibility(controller.themeHeaderTitle) == "Theme: Ocean")
        let settingsLabels = [
            UIStrings.appearance, UIStrings.filenameFormat, UIStrings.exportFolder, UIStrings.confirmReset,
            UIStrings.defaultTemplate, UIStrings.choose, UIStrings.clear,
        ]
        #expect(settingsLabels.allSatisfy { !$0.isEmpty } && Set(settingsLabels).count == settingsLabels.count)
        #expect(AppearanceSetting.allCases.map(UIStrings.appearanceName).allSatisfy { !$0.isEmpty })
        let dialogButtons = [UIStrings.save, UIStrings.dontSave, UIStrings.cancel, UIStrings.startOverButton]
        #expect(dialogButtons.allSatisfy { !$0.isEmpty } && Set(dialogButtons).count == dialogButtons.count)
        #expect(UIStrings.saveChangesTitle(UIStrings.untitled) == "Save changes to Untitled?")
        #expect(!UIStrings.saveThemeAccessibility.isEmpty && !UIStrings.themeNamePrompt.isEmpty)
    }
}
