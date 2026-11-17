import Foundation
import Testing

@testable import SunshotCore

@Suite("Backdrop catalogs")
struct BackdropCatalogTests {
    /// Names that would suggest third-party artwork or branding.
    private static let bannedTerms = ["apple", "macos", "ios", "instagram", "unsplash", "spark", "google", "adobe"]

    @Test("[S3-AC4] ≥24 swatches: ≥6 neutrals incl. black and white, ≥18 hues, unique hex, from bundled JSON")
    func swatches() throws {
        let groups = try BackdropCatalog.swatchGroups()
        let neutrals = try #require(groups.first { $0.id == "neutrals" }).swatches
        let hues = try #require(groups.first { $0.id == "hues" }).swatches
        #expect(neutrals.count >= 6 && hues.count >= 18)
        #expect(neutrals.contains { $0.color == .white } && neutrals.contains { $0.color == .black })
        let all = groups.flatMap(\.swatches)
        #expect(all.count >= 24)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.allSatisfy { $0.color.alpha == 1 && $0.id == $0.color.hexString })
        #expect(all.contains { $0.color == SunshotDefaults.backdropColor }, "the default colour is a swatch")
    }

    @Test("[S3-AC7] ≥16 gradient presets, linear and radial mixed, unique and unbranded")
    func gradientPresets() throws {
        let presets = try BackdropCatalog.gradientPresets()
        #expect(presets.count >= 16)
        #expect(presets.contains { $0.spec.kind == .linear } && presets.contains { $0.spec.kind == .radial })
        #expect(Set(presets.map(\.id)).count == presets.count)
        #expect(Set(presets.map(\.name)).count == presets.count)
        #expect(Set(presets.map(\.spec)).count == presets.count)
        let names = presets.map { "\($0.id) \($0.name)".lowercased() }
        #expect(names.allSatisfy { name in !Self.bannedTerms.contains { name.contains($0) } })
        #expect(presets.first?.spec == SunshotDefaults.gradient, "the default gradient is the first preset")
    }

    @Test("[S3-AC15] ≥8 generated wallpapers, payload ≤3 MB, each with a seed recipe as provenance")
    func wallpapers() throws {
        let wallpapers = try BackdropCatalog.wallpapers()
        #expect(wallpapers.count >= 8)
        #expect(Set(wallpapers.map(\.seed)).count == wallpapers.count)
        #expect(wallpapers.allSatisfy { !$0.palette.isEmpty && $0.fieldCount > 0 && !$0.fields.isEmpty })
        #expect(wallpapers.first == SunshotDefaults.wallpaper, "the default wallpaper is the first one")
        let bytes = try BackdropCatalog.resourceNames.map { name in
            let url = try #require(BackdropCatalog.resourceURL(name))
            return try Data(contentsOf: url).count
        }
        #expect(bytes.reduce(0, +) <= 3_000_000)
        let names = wallpapers.map { "\($0.id) \($0.name)".lowercased() }
        #expect(names.allSatisfy { name in !Self.bannedTerms.contains { name.contains($0) } })
    }

    @Test("[S3-AC15] the repository holds no wallpaper bitmaps: every bundled resource is a JSON recipe")
    func provenance() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SunshotCore/Resources")
        let files = try FileManager.default.contentsOfDirectory(atPath: resources.path)
        #expect(!files.isEmpty)
        #expect(files.allSatisfy { $0.hasSuffix(".json") }, "unexpected resource files: \(files)")
    }

    @Test("[S3-AC4] [S3-AC7] [S3-AC15] invalid catalog data is rejected")
    func validation() {
        func data(_ text: String) -> Data { Data(text.utf8) }
        let stops = #"[{"position":0,"hex":"000000"},{"position":1,"hex":"FFFFFF"}]"#
        let gradient = #"{"id":"a","name":"A","kind":"linear","angle":90,"stops":\#(stops)}"#
        let invalid: [(String, () throws -> Void)] = [
            (
                "duplicate hex",
                {
                    _ = try BackdropCatalog.decodeSwatches(
                        data(
                            #"[{"id":"g","name":"G","swatches":[{"name":"A","hex":"000000"},{"name":"B","hex":"000000"}]}]"#
                        ))
                }
            ),
            (
                "bad hex",
                {
                    _ = try BackdropCatalog.decodeSwatches(
                        data(
                            #"[{"id":"g","name":"G","swatches":[{"name":"A","hex":"12"}]}]"#))
                }
            ),
            (
                "empty name",
                {
                    _ = try BackdropCatalog.decodeSwatches(
                        data(
                            #"[{"id":"g","name":"G","swatches":[{"name":" ","hex":"123456"}]}]"#))
                }
            ),
            ("duplicate gradient", { _ = try BackdropCatalog.decodeGradients(data("[\(gradient),\(gradient)]")) }),
            (
                "one stop",
                {
                    _ = try BackdropCatalog.decodeGradients(
                        data(
                            #"[{"id":"a","name":"A","kind":"linear","angle":0,"stops":[{"position":0,"hex":"000000"}]}]"#
                        ))
                }
            ),
            (
                "wallpaper without palette",
                {
                    _ = try BackdropCatalog.decodeWallpapers(
                        data(
                            #"[{"id":"w","name":"W","seed":1,"base":\#(gradient),"palette":[],"fields":3}]"#))
                }
            ),
            (
                "duplicate seed",
                {
                    let wallpaper =
                        #"{"id":"w","name":"W","seed":1,"base":\#(gradient),"palette":["FFFFFF"],"fields":3}"#
                    let twin = #"{"id":"v","name":"V","seed":1,"base":\#(gradient),"palette":["FFFFFF"],"fields":3}"#
                    _ = try BackdropCatalog.decodeWallpapers(data("[\(wallpaper),\(twin)]"))
                }
            ),
            ("not JSON", { _ = try BackdropCatalog.decodeWallpapers(data("nope")) }),
        ]
        let accepted = invalid.filter { _, decode in (try? decode()) != nil }.map(\.0)
        #expect(accepted.isEmpty, "accepted invalid catalogs: \(accepted)")
        #expect(BackdropCatalogError.missingResource("x") != .invalid("x"))
    }
}
