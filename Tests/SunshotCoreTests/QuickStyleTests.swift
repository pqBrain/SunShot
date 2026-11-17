import Foundation
import SunshotCore
import Testing

@Suite("Default style and hover window picking")
struct QuickStyleTests {
    @Test("[S16-AC3] the default style keeps the whole style but drops per-image parts, and round-trips as JSON")
    func styleOnly() throws {
        var project = Project()
        project.padding = 123
        project.annotationLayer = AnnotationLayer(stepFormat: .letters)
        project.collage = "pair"
        let style = QuickStyle(project: project, savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(style.project.padding == 123)
        #expect(style.project.annotationLayer == nil && style.project.animation == nil && style.project.collage == nil)
        let decoded = try QuickStyle.decode(try style.encoded())
        #expect(decoded == style)
    }

    @Test("[S16-AC3] unreadable data and styles from a newer version are refused")
    func refusesBadData() throws {
        #expect(throws: (any Error).self) { try QuickStyle.decode(Data("nope".utf8)) }
        var newer = QuickStyle(project: Project())
        newer.schemaVersion = QuickStyle.currentSchemaVersion + 1
        #expect(throws: DocumentFormatError.self) { try QuickStyle.decode(try newer.encoded()) }
    }

    private let windows = [
        CapturableWindow(
            id: 1, title: "Front", appName: "Notes", width: 400, height: 300,
            frame: LayoutRect(x: 100, y: 100, width: 400, height: 300)),
        CapturableWindow(
            id: 2, title: "Back", appName: "Mail", width: 800, height: 600,
            frame: LayoutRect(x: 0, y: 0, width: 800, height: 600)),
        CapturableWindow(id: 3, title: "No frame", appName: "Ghost", width: 800, height: 600),
        CapturableWindow(
            id: 4, title: "", appName: "Sunshot", width: 800, height: 600,
            frame: LayoutRect(x: 0, y: 0, width: 800, height: 600)),
        CapturableWindow(
            id: 5, title: "Item", appName: "Menu", width: 30, height: 22,
            frame: LayoutRect(x: 10, y: 10, width: 30, height: 22)),
    ]

    @Test("[S16-AC4] the front-most window under the pointer is picked; the desktop picks nothing")
    func hitTest() {
        let candidates = WindowPicking.candidates(windows, excludingApp: "Sunshot")
        #expect(candidates.map(\.id) == [1, 2])
        #expect(WindowPicking.window(at: (150, 150), in: candidates)?.id == 1)
        #expect(WindowPicking.window(at: (50, 50), in: candidates)?.id == 2)
        #expect(WindowPicking.window(at: (500, 400), in: candidates)?.id == 2)
        #expect(WindowPicking.window(at: (499, 100), in: candidates)?.id == 1)
        #expect(WindowPicking.window(at: (800, 600), in: candidates) == nil)
        #expect(WindowPicking.window(at: (-5, 10), in: candidates) == nil)
    }

    @Test("[S16-AC4] screen frames convert to top-left space and window frames to each screen's own coordinates")
    func coordinates() {
        // Main display 1440×900; a second display to its right, top edges aligned at 1080 high.
        let main = WindowPicking.topLeftFrame(x: 0, y: 0, width: 1440, height: 900, mainHeight: 900)
        #expect(main == LayoutRect(x: 0, y: 0, width: 1440, height: 900))
        let side = WindowPicking.topLeftFrame(x: 1440, y: -180, width: 1920, height: 1080, mainHeight: 900)
        #expect(side == LayoutRect(x: 1440, y: 0, width: 1920, height: 1080))
        let window = LayoutRect(x: 1500, y: 40, width: 600, height: 400)
        #expect(WindowPicking.local(window, on: side) == LayoutRect(x: 60, y: 40, width: 600, height: 400))
    }
}
