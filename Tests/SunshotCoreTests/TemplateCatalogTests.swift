import Foundation
import Testing

@testable import SunshotCore

@Suite("Template catalog")
struct TemplateCatalogTests {
    let catalog: TemplateCatalog

    init() throws { catalog = try TemplateCatalog.load() }

    static func decode(_ templates: [[String: Any]]) throws -> TemplateCatalog {
        let first: [String: Any] = ["id": "screenshot", "name": "Screenshot"]
        let data = try JSONSerialization.data(withJSONObject: ["templates": [first] + templates])
        return try TemplateCatalog.decode(
            data, gradients: BackdropCatalog.gradientPresets(), wallpapers: BackdropCatalog.wallpapers(),
            layouts: LayoutPresetCatalog.load(), devices: DeviceCatalog.load())
    }

    @Test("[S12-AC15] bundled templates load, start with the plain document and include every device layout")
    func bundled() throws {
        let templates = catalog.templates
        #expect(templates.count >= 12)
        #expect(templates.first?.id == "screenshot" && templates.first?.name == "Screenshot")
        #expect(templates.first?.project == Project())
        #expect(Set(templates.map(\.id)).count == templates.count)
        #expect(Set(templates.map { $0.name.lowercased() }).count == templates.count)
        #expect(templates.allSatisfy { !$0.summary.isEmpty })
        let devices = templates.filter(\.usesDevice)
        #expect(devices.count >= 8)
        let arrangements = Set(devices.compactMap { $0.project.frame.device?.arrangement })
        #expect(arrangements == ["single", "pair", "trio", "laptop-phone", "monitor-phone", "tablet-phone"])
        #expect(Set(devices.compactMap { $0.project.frame.device?.model }) == ["phone", "tablet", "laptop", "desktop"])
        // Device templates never also carry a frame kind; layout presets resolve to their transform.
        #expect(devices.allSatisfy { $0.project.frame.kind == .none })
        let tilted = try #require(templates.first { $0.id == "tablet-tabletop" })
        #expect(tilted.project.placement.layoutPresetID == "tabletop" && !tilted.project.placement.transform.isFlat)
        let trio = try #require(templates.first { $0.id == "pocket-trio" })
        #expect(trio.project.canvas == .ratio(16.0 / 9.0))
        #expect(trio.project.backdrop.kind == .image)
    }

    @Test("[S12-AC15] sample sizes and lookups by id or name")
    func lookups() throws {
        #expect(catalog.template(matching: "Screenshot")?.id == "screenshot")
        #expect(catalog.template(matching: "pocket-trio")?.name == "Pocket Trio")
        #expect(catalog.template(matching: "POCKET TRIO")?.id == "pocket-trio")
        #expect(catalog.template(matching: "deleted-template")?.id == "screenshot")
        #expect(TemplateCatalog(templates: []).template(matching: "x") == nil)
        let tablet = try #require(catalog.template(matching: "tablet-tabletop"))
        #expect(tablet.sampleSize() == PixelSize(width: 2752, height: 2064))
        let combo = try #require(catalog.template(matching: "desk-and-pocket"))
        #expect(combo.sampleSize() == PixelSize(width: 2560, height: 1600))
        #expect(catalog.templates[0].sampleSize() == PixelSize(width: 1280, height: 800))
    }

    @Test("[S12-AC16] invalid templates are rejected")
    func rejectsInvalid() throws {
        let valid: [String: Any] = [
            "id": "ok", "name": "OK", "canvas": ["width": 1200, "height": 800], "backdrop": ["solid": "#112233"],
            "corners": ["style": "round", "radius": 40], "shadow": ["style": "hug"], "frame": "card", "padding": 10,
        ]
        let decoded = try Self.decode([valid])
        let project = try #require(decoded.templates.last?.project)
        #expect(project.canvas == .exact(PixelSize(width: 1200, height: 800)) && project.padding == 10)
        #expect(project.border == Border(style: .round, radius: 40) && project.shadow.style == .hug)
        #expect(project.frame.kind == .card && project.backdrop == .solid(RGBAColor(rgb: 0x112233)))
        let bad: [(String, [String: Any])] = [
            ("gradient", ["backdrop": ["gradient": "nope"]]),
            ("wallpaper", ["backdrop": ["wallpaper": "nope"]]),
            ("two kinds", ["backdrop": ["solid": "#000", "none": true]]),
            ("colour", ["backdrop": ["solid": "blue"]]),
            ("layout", ["layout": "nope"]),
            ("device", ["device": ["model": "watch"]]),
            ("finish", ["device": ["model": "phone", "finish": "gold"]]),
            ("combo model", ["device": ["model": "phone", "arrangement": "laptop-phone"]]),
            ("frame and device", ["frame": "card", "device": ["model": "phone"]]),
            ("frame", ["frame": "hologram"]),
            ("padding", ["padding": -1]),
            ("radius", ["corners": ["radius": 500]]),
            ("canvas", ["canvas": ["width": 0, "height": 10]]),
            ("ratio", ["canvas": ["ratio": -1]]),
        ]
        for (name, fields) in bad {
            let entry = fields.merging(["id": "bad", "name": "Bad"]) { current, _ in current }
            #expect(throws: TemplateCatalogError.self, "\(name)") { try Self.decode([entry]) }
        }
        #expect(throws: TemplateCatalogError.self) { try Self.decode([["id": "screenshot", "name": "Again"]]) }
        #expect(throws: TemplateCatalogError.self) { try Self.decode([["id": "two", "name": "screenshot"]]) }
        let plainFirst = try JSONSerialization.data(withJSONObject: [
            "templates": [["id": "screenshot", "name": "Screenshot", "padding": 10]]
        ])
        #expect(throws: TemplateCatalogError.self) {
            try TemplateCatalog.decode(
                plainFirst, gradients: [], wallpapers: [], layouts: LayoutPresetCatalog.load(), devices: .bundled)
        }
        #expect(throws: TemplateCatalogError.self) {
            try TemplateCatalog.decode(
                Data("[]".utf8), gradients: [], wallpapers: [], layouts: LayoutPresetCatalog.load(), devices: .bundled)
        }
        #expect(TemplateCatalogError.missingResource != .invalid("x"))
    }

}
