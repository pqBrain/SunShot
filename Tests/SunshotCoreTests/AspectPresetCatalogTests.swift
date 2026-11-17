import Foundation
import Testing

@testable import SunshotCore

@Suite("AspectPresetCatalog")
struct AspectPresetCatalogTests {
    @Test("[S0] bundled catalogue loads and is valid")
    func bundledCatalogueLoads() throws {
        let groups = try AspectPresetCatalog.load()
        #expect(!groups.isEmpty)
        #expect(groups.flatMap(\.presets).contains { $0.id == "general.square" && $0.ratio == 1 })
    }

    @Test("[S0] labels agree with ratios")
    func labelsMatchRatios() throws {
        for preset in try AspectPresetCatalog.load().flatMap(\.presets) {
            let parts = preset.label.split(separator: ":").compactMap { Double($0) }
            try #require(parts.count == 2, "label \(preset.label) for \(preset.id)")
            #expect(abs(parts[0] / parts[1] - preset.ratio) < 0.001, "\(preset.id)")
        }
    }

    @Test(
        "[S0] rejects invalid catalogues",
        arguments: [
            #"[{"id":"g","name":"G","presets":[{"id":"a","name":"A","ratio":1,"label":"1:1"},{"id":"a","name":"B","ratio":1,"label":"1:1"}]}]"#,
            #"[{"id":"g","name":"G","presets":[{"id":"a","name":"A","ratio":0,"label":"0:1"}]}]"#,
            #"[{"id":"g","name":"G","presets":[{"id":"a","name":"","ratio":1,"label":"1:1"}]}]"#,
        ])
    func rejectsInvalid(json: String) {
        #expect(throws: AspectPresetCatalogError.self) { try AspectPresetCatalog.decode(Data(json.utf8)) }
    }
}
