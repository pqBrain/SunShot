import Foundation
import Testing

@testable import SunshotCore

@Suite("Backdrop model")
struct BackdropModelTests {
    @Test("[S3-AC1] each type remembers its last settings: Solid → Gradient → Solid restores the colour")
    func perTypeMemory() {
        var project = Project()
        #expect(project.backdropSettings.kind == .solid)
        let coral = RGBAColor(rgb: 0xFF7F50)
        project.backdrop = .solid(coral)
        project.backdropSettings.kind = .gradient
        #expect(project.backdrop == .gradient(SunshotDefaults.gradient))
        project.backdropSettings.kind = .none
        #expect(project.backdrop == .none)
        project.backdropSettings.kind = .solid
        #expect(project.backdrop == .solid(coral))
        project.backdropSettings.kind = .image
        #expect(project.backdrop == .image(.wallpaper(SunshotDefaults.wallpaper)))
        #expect(project.backdropSettings.mediaReference == nil)
        let reference = MediaReference(id: "a", fileName: "a.png", pixelSize: PixelSize(width: 2, height: 2))
        project.backdrop = .image(.file(reference))
        #expect(project.backdropSettings.mediaReference == reference)
        project.backdrop = .none
        #expect(project.backdropSettings.solidColor == coral, "None keeps every remembered value")
    }

    @Test("[S3-AC2] only fully opaque backdrops skip the transparency grid")
    func opacity() {
        let reference = MediaReference(id: "a", fileName: nil, pixelSize: PixelSize(width: 1, height: 1))
        #expect(!Backdrop.none.isOpaque)
        #expect(Backdrop.solid(.white).isOpaque)
        #expect(!Backdrop.solid(RGBAColor(rgb: 0xFF0000, alpha: 0.5)).isOpaque)
        #expect(Backdrop.gradient(SunshotDefaults.gradient).isOpaque)
        #expect(Backdrop.image(.wallpaper(SunshotDefaults.wallpaper)).isOpaque)
        #expect(!Backdrop.image(.file(reference)).isOpaque)
        #expect(BackdropKind.allCases.map { $0.rawValue } == ["none", "solid", "gradient", "image"])
        #expect(Backdrop.image(.file(reference)).kind == .image)
    }

    @Test("[S3-AC17] the backdrop settings round-trip through JSON")
    func coding() throws {
        var project = Project(backdrop: .gradient(SunshotDefaults.gradient))
        project.backdropSettings.solidColor = RGBAColor(rgb: 0x123456)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded == project)
    }

    @Test("[S3-AC15] wallpapers are generated from their seed: same recipe, same colour fields")
    func wallpaperGenerator() {
        let wallpaper = SunshotDefaults.wallpaper
        #expect(wallpaper.fields == wallpaper.fields)
        #expect(wallpaper.fields.count == wallpaper.fieldCount)
        let other = Wallpaper(
            id: "x", name: "X", seed: wallpaper.seed + 1, base: wallpaper.base, palette: wallpaper.palette,
            fieldCount: 40)
        #expect(other.fieldCount == 16)
        #expect(other.fields.prefix(6) != wallpaper.fields[...])
        let field = wallpaper.fields[0]
        #expect(field.weight(atDistanceSquared: 0) == field.strength)
        #expect(field.weight(atDistanceSquared: field.radius * field.radius * 2) == 0)
        let empty = Wallpaper(id: "e", name: "E", seed: 1, base: wallpaper.base, palette: [], fieldCount: 3)
        #expect(empty.fields.isEmpty)
        var random = SeededRandom(seed: 7)
        let values = (0..<100).map { _ in random.next(in: 2...3) }
        #expect(values.allSatisfy { (2...3).contains($0) })
    }
}
