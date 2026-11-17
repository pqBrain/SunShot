import Foundation
import Testing

@testable import SunshotCore

@Suite("Settings model")
struct AppSettingsTests {
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let date = Date(timeIntervalSince1970: 1_763_400_000)

    @Test("[S7-AC12] [S7-AC16] defaults: system appearance, default template format, ask each time, confirm on")
    func defaults() {
        let settings = AppSettings()
        #expect(settings.appearance == .system)
        #expect(settings.filenameTemplate == "{TEMPLATE}_{SCALE}_sunshot_{DATE}")
        #expect(settings.exportFolder == nil)
        #expect(settings.confirmReset)
        #expect(settings.defaultTemplate == "Screenshot")
        #expect(AppSettings.defaults == settings)
    }

    @Test("[S7-AC14] live preview follows the S4 rules; empty warns and uses the default")
    func filenamePreview() {
        let custom = FilenamePreview.preview(template: "{TEMPLATE}-{WIDTH}x{HEIGHT}", date: date, timeZone: utc)
        #expect(custom.name == "screenshot-1128x728.png" && custom.warning == nil)
        let empty = FilenamePreview.preview(template: "  ", date: date, timeZone: utc)
        #expect(empty.warning == "Using the default format")
        #expect(empty.name == "screenshot_1x_sunshot_2025-11-17_17-20-00.png")
        #expect(FilenamePreview.preview(template: "{RANDOM}", date: date).name == "a1b2c3.png")
    }

    @Test("[S7-AC14] a blank template falls back to the default for exports")
    func effectiveTemplate() {
        #expect(AppSettings(filenameTemplate: "").effectiveFilenameTemplate == SunshotDefaults.filenameTemplate)
        #expect(AppSettings(filenameTemplate: "{DATE}").effectiveFilenameTemplate == "{DATE}")
    }

    @Test("[S7-AC15] name collisions append \" 2\", \" 3\" instead of overwriting")
    func uniqueNames() {
        var existing: Set<String> = []
        #expect(ExportFileNaming.uniqueName("shot.png") { existing.contains($0) } == "shot.png")
        existing = ["shot.png", "shot 2.png"]
        #expect(ExportFileNaming.uniqueName("shot.png") { existing.contains($0) } == "shot 3.png")
        existing = ["shot"]
        #expect(ExportFileNaming.uniqueName("shot") { existing.contains($0) } == "shot 2")
    }

    @Test("[S7-AC6] recent list: most recent first, no duplicates, at most 10")
    func recentList() {
        var list = RecentList<String>()
        for index in 1...12 { list.note("doc\(index)") }
        #expect(list.items.count == 10)
        #expect(list.items.first == "doc12" && list.items.last == "doc3")
        list.note("doc5")
        #expect(list.items.first == "doc5" && list.items.count == 10 && list.items.filter { $0 == "doc5" }.count == 1)
        list.remove { $0 == "doc5" }
        #expect(!list.items.contains("doc5"))
        list.clear()
        #expect(list.items.isEmpty)
        #expect(RecentList(items: (1...15).map(String.init)).items.count == 10)
    }
}
