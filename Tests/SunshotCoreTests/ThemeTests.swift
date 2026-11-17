import Foundation
import Testing

@testable import SunshotCore

@Suite("Themes")
struct ThemeTests {
    private var styled: Project {
        var project = Project(
            canvas: .ratio(2), backdrop: .gradient(SunshotDefaults.gradient), padding: 30,
            border: Border(style: .round, radius: 50), shadow: Shadow(style: .hug, intensity: .low),
            export: ExportOptions(format: .heic, scale: .x1))
        project.backdropSettings.solidColor = .black
        return project
    }

    @Test("[S7-AC9] a theme holds exactly the style fields (backdrop, border, shadow), not canvas or export")
    func extractFields() throws {
        let theme = try Theme.extract(from: styled, name: "Ocean")
        #expect(Set(theme.style.keys) == Set(Theme.fields.map(\.key)))
        #expect(Set(theme.style.keys) == ["backdrop", "border", "shadow"])
        #expect(theme.style["border"] == (try JSONValue(encoding: Border(style: .round, radius: 50))))
        let encoded = try String(decoding: JSONEncoder().encode(theme), as: UTF8.self)
        #expect(!encoded.contains("canvas") && !encoded.contains("export") && !encoded.contains("padding"))
    }

    @Test("[S7-AC9] user images are never stored in a theme")
    func userImagesStripped() throws {
        var project = styled
        project.backdrop = .image(
            .file(MediaReference(id: "m", fileName: "a.png", pixelSize: PixelSize(width: 2, height: 2))))
        let theme = try Theme.extract(from: project, name: "Photo")
        let applied = try theme.apply(to: Project())
        #expect(applied.backdrop == .image(.wallpaper(SunshotDefaults.wallpaper)))
    }

    @Test("[S7-AC10] applying replaces style only; content-independent fields stay")
    func applyKeepsLayout() throws {
        let theme = try Theme.extract(from: styled, name: "Paper")
        let target = Project(
            canvas: .exact(PixelSize(width: 800, height: 600)), padding: 12, export: ExportOptions(format: .jpeg))
        let result = try theme.apply(to: target)
        #expect(result.border == styled.border && result.shadow == styled.shadow)
        #expect(result.backdropSettings == styled.backdropSettings)
        #expect(result.canvas == target.canvas && result.export == target.export && result.padding == target.padding)
        #expect(theme.matches(result) && !theme.matches(target))
    }

    @Test("[S7-AC10] a theme missing a field (older theme) applies that field's default")
    func missingFieldUsesDefault() throws {
        var theme = try Theme.extract(from: styled, name: "Old")
        theme.style["shadow"] = nil
        theme.style["border"] = .object(["style": .string("sharp")])
        let result = try theme.apply(to: styled)
        #expect(result.shadow == Shadow())
        #expect(result.border == Border(style: .sharp))
        theme.style["border"] = .string("garbage")
        #expect(throws: (any Error).self) { try theme.apply(to: styled) }
        #expect(!theme.matches(styled))
    }

    @Test("[S7-AC10] header: No Theme, name, \"name (modified)\", and follows renames")
    func headerRule() throws {
        let ocean = try Theme.extract(from: styled, name: "Ocean")
        let applied = try ocean.apply(to: Project())
        #expect(Theme.headerTitle(applied: nil, project: applied, library: [ocean]) == "No Theme")
        #expect(Theme.headerTitle(applied: ocean, project: applied, library: [ocean]) == "Ocean")
        var edited = applied
        edited.border.radius = 10
        #expect(Theme.headerTitle(applied: ocean, project: edited, library: [ocean]) == "Ocean (modified)")
        // Editing back to the theme's value reads unmodified again; content-only changes never count.
        edited.border.radius = 50
        edited.canvas = .ratio(1)
        #expect(Theme.headerTitle(applied: ocean, project: edited, library: [ocean]) == "Ocean")
        var renamed = ocean
        renamed.name = "Sea"
        #expect(Theme.headerTitle(applied: ocean, project: applied, library: [renamed]) == "Sea")
    }

    @Test("[S7-AC11] the header of a deleted theme reads No Theme")
    func deletedTheme() throws {
        let ocean = try Theme.extract(from: styled, name: "Ocean")
        #expect(Theme.headerTitle(applied: ocean, project: styled, library: []) == Theme.noThemeTitle)
    }

    @Test("[S7-AC9] names: empty, whitespace, > 60 characters and duplicates (case-insensitive) are rejected")
    func nameValidation() throws {
        let existing = [try Theme.extract(from: styled, name: "Ocean", id: "o")]
        #expect(ThemeName.validate("", existing: existing) == .failure(.empty))
        #expect(ThemeName.validate("   \n", existing: existing) == .failure(.empty))
        #expect(ThemeName.validate(String(repeating: "a", count: 61), existing: existing) == .failure(.tooLong))
        #expect(
            ThemeName.validate(String(repeating: "a", count: 60), existing: existing)
                == .success(String(repeating: "a", count: 60)))
        #expect(ThemeName.validate(" OCEAN ", existing: existing) == .failure(.duplicate(existingID: "o")))
        #expect(ThemeName.validate("ocean", existing: existing, excluding: "o") == .success("ocean"))
        #expect(ThemeName.validate("  Paper ", existing: existing) == .success("Paper"))
        for problem in [ThemeName.Problem.empty, .tooLong, .duplicate(existingID: "o")] {
            #expect(!problem.message.isEmpty)
        }
    }

    @Test("[S7-AC9] illegal file-name characters are stripped from the file name only")
    func fileNames() {
        #expect(ThemeName.fileName(for: "Ocean") == "ocean.json")
        #expect(ThemeName.fileName(for: "Blue/Green: \"Night\"?") == "bluegreen night.json")
        #expect(ThemeName.fileName(for: "..hidden") == "hidden.json")
        #expect(ThemeName.fileName(for: "///") == "theme.json")
        #expect(ThemeName.fileName(for: "Ocean", taken: ["ocean.json", "ocean-2.json"]) == "ocean-3.json")
    }

    @Test("[S7-AC11] duplicates are named \"copy\", then \"copy 2\"")
    func copyNames() throws {
        let ocean = try Theme.extract(from: styled, name: "Ocean")
        var copy = ocean
        copy.name = "Ocean copy"
        #expect(ThemeName.copyName(of: "Ocean", existing: [ocean]) == "Ocean copy")
        #expect(ThemeName.copyName(of: "Ocean", existing: [ocean, copy]) == "Ocean copy 2")
        #expect(ThemeName.copyName(of: String(repeating: "x", count: 60), existing: []).count <= ThemeName.maxLength)
    }
}
