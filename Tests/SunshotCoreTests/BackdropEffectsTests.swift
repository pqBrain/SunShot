import Foundation
import Testing

@testable import SunshotCore

@Suite("Backdrop effects model")
struct BackdropEffectsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("[S8-AC2] a project saved before S8 decodes with every effect at its default")
    func legacyProject() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project())) as? [String: Any]
        var settings = legacy?["backdropSettings"] as? [String: Any]
        settings?["effects"] = nil
        settings?["autoShuffle"] = nil
        legacy?["backdropSettings"] = settings
        let data = try JSONSerialization.data(withJSONObject: try #require(legacy))
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded == Project())
        #expect(decoded.backdropSettings.effects.isIdentity)
    }

    @Test("[S8-AC2] partial and out-of-range effect values decode to defaults / clamped values")
    func tolerantDecoding() throws {
        let effects = try decode(
            BackdropEffects.self,
            #"{"adjustments":{"blur":900,"saturation":-1},"pattern":{"kind":"sparkles","thickness":9},"#
                + #""vignette":{"style":"dark"},"overlay":{"opacity":2,"position":"below"}}"#)
        #expect(effects.adjustments == BackdropAdjustments(blur: 50, noise: 0, saturation: 0, opacity: 1))
        #expect(effects.pattern == BackdropPattern(kind: .none, thickness: 3))
        #expect(effects.vignette == Vignette(style: .dark, spread: 0.5, intensity: 0.5))
        #expect(effects.overlay == OverlayTexture(kind: .none, opacity: 1, position: .below))
        #expect(try decode(BackdropEffects.self, "{}") == BackdropEffects())
        #expect(try decode(BackdropPattern.self, "{}") == BackdropPattern())
        #expect(try decode(OverlayTexture.self, "{}") == OverlayTexture())
        #expect(try decode(Vignette.self, "{}") == Vignette())
        #expect(try decode(BackdropAdjustments.self, "{}") == BackdropAdjustments())
    }

    @Test("[S8-AC2] effects round-trip; setters clamp; NaN falls back to the default")
    func roundTripAndClamp() throws {
        var project = Project()
        project.backdropSettings.effects = BackdropEffects(
            adjustments: BackdropAdjustments(blur: 12, noise: 0.3, saturation: 1.2, opacity: 0.8),
            pattern: BackdropPattern(kind: .rays, intensity: 0.7, thickness: 1.5, color: .white),
            vignette: Vignette(style: .light, spread: 0.2, intensity: 0.9),
            overlay: OverlayTexture(kind: .dapple, opacity: 0.4, position: .below))
        project.backdropSettings.autoShuffle = 42
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data) == project)

        var adjustments = BackdropAdjustments()
        adjustments.noise = 5
        adjustments.opacity = -1
        adjustments.saturation = .nan
        adjustments.blur = .infinity
        #expect(adjustments == BackdropAdjustments(blur: 0, noise: 1, saturation: 1, opacity: 0))
        var pattern = BackdropPattern()
        pattern.intensity = .nan
        pattern.thickness = 0
        #expect(pattern.intensity == BackdropPattern.defaultIntensity && pattern.thickness == 0.25)
        var vignette = Vignette()
        vignette.spread = 3
        vignette.intensity = -2
        #expect(vignette == Vignette(spread: 1, intensity: 0))
        var overlay = OverlayTexture()
        overlay.opacity = .nan
        #expect(overlay.opacity == OverlayTexture.defaultOpacity)
    }

    @Test("[S8-AC1] identity rules: defaults and zero strengths draw nothing")
    func identity() {
        #expect(BackdropEffects().isIdentity)
        #expect(BackdropEffects(pattern: BackdropPattern(kind: .grid, intensity: 0)).isIdentity)
        #expect(BackdropEffects(pattern: BackdropPattern(kind: .grid, color: .clear)).isIdentity)
        #expect(BackdropEffects(vignette: Vignette(style: .dark, intensity: 0)).isIdentity)
        #expect(BackdropEffects(overlay: OverlayTexture(kind: .leaves, opacity: 0)).isIdentity)
        let above = BackdropEffects(overlay: OverlayTexture(kind: .leaves))
        #expect(above.isIdentityBelowContent && above.drawsAboveContent && !above.isIdentity)
        let below = BackdropEffects(overlay: OverlayTexture(kind: .leaves, position: .below))
        #expect(!below.isIdentityBelowContent && !below.drawsAboveContent)
        #expect(!BackdropEffects(adjustments: BackdropAdjustments(blur: 1)).isIdentity)
    }
}

@Suite("Palette extraction and auto backgrounds")
struct AutoBackgroundTests {
    /// Straight RGBA pixels: `count` of each colour.
    private func pixels(_ colors: [(UInt32, Int)], alpha: UInt8 = 255) -> [UInt8] {
        colors.flatMap { rgb, count in
            Array(repeating: [UInt8(rgb >> 16 & 0xFF), UInt8(rgb >> 8 & 0xFF), UInt8(rgb & 0xFF), alpha], count: count)
                .flatMap(\.self)
        }
    }

    private func bytes(_ color: RGBAColor) -> [Int] {
        [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
    }

    @Test("[S8-AC14] six colours by prominence; a four-colour image yields its four colours; deterministic")
    func fourColours() {
        let input = pixels([(0x3060E0, 400), (0xE04030, 300), (0x30B050, 200), (0xF0C020, 100)])
        let palette = PaletteExtractor.extract(rgba: input)
        #expect(palette.count == 6)
        #expect(palette == PaletteExtractor.extract(rgba: input))
        let expected: [UInt32] = [0x3060E0, 0xE04030, 0x30B050, 0xF0C020]
        for (index, rgb) in expected.enumerated() {
            let target = [Int(rgb >> 16 & 0xFF), Int(rgb >> 8 & 0xFF), Int(rgb & 0xFF)]
            #expect(zip(bytes(palette[index]), target).allSatisfy { abs($0 - $1) <= 8 }, "\(index): \(palette[index])")
        }
    }

    @Test("[S8-AC14] transparent pixels are ignored; one colour gives six tints; transparent gives none")
    func edgeCases() {
        let withHidden = pixels([(0x20A0A0, 50)]) + pixels([(0xFF00FF, 500)], alpha: 10)
        let palette = PaletteExtractor.extract(rgba: withHidden)
        #expect(zip(bytes(palette[0]), [32, 160, 160]).allSatisfy { abs($0 - $1) <= 8 })
        #expect(!palette.contains { bytes($0) == [255, 0, 255] })
        #expect(Set(palette.map(bytes)).count == 6, "six distinct colours from one")
        #expect(PaletteExtractor.extract(rgba: pixels([(0x000000, 10)], alpha: 0)).isEmpty)
        #expect(PaletteExtractor.extract(rgba: []).isEmpty)
        #expect(PaletteExtractor.extract(rgba: pixels([(0x102030, 10)]), count: 0).isEmpty)
        #expect(Set(PaletteExtractor.extract(rgba: pixels([(0xFFFFFF, 10)])).map(bytes)).count == 6)
        #expect(PaletteExtractor.extract(rgba: pixels([(0x000000, 10)]), count: 12).count == 12)
    }

    @Test("[S8-AC15] five opaque suggestions built from palette colours, deterministic per palette and shuffle")
    func suggestions() {
        let palette = [0x3060E0, 0xE04030, 0x30B050, 0xF0C020, 0x202030, 0xF0F0F0].map { RGBAColor(rgb: UInt32($0)) }
        let first = AutoBackground.suggestions(palette: palette, shuffle: 0)
        #expect(first.count == 5)
        #expect(first == AutoBackground.suggestions(palette: palette, shuffle: 0))
        #expect(first != AutoBackground.suggestions(palette: palette, shuffle: 1))
        #expect(Set(first.map(\.id)).count == 5)
        #expect(first.allSatisfy(AutoBackground.isGenerated))
        #expect(!AutoBackground.isGenerated(SunshotDefaults.wallpaper))
        #expect(first[1].base.kind == .radial)
        for wallpaper in first {
            #expect(wallpaper.base.isOpaque && wallpaper.palette.allSatisfy { $0.alpha == 1 })
            #expect(!wallpaper.fields.isEmpty)
        }
        // Style 0 uses the palette colours as they are.
        let raw = Set(palette.map(bytes))
        #expect(first[0].palette.allSatisfy { raw.contains(bytes($0)) })
        #expect(AutoBackground.suggestions(palette: [], shuffle: 3).isEmpty)
    }

    @Test("[S8-AC16] the next shuffle value is deterministic and always different")
    func nextShuffle() {
        #expect(AutoBackground.nextShuffle(after: 0) == AutoBackground.nextShuffle(after: 0))
        var value: UInt64 = 0
        var seen: Set<UInt64> = [0]
        for _ in 0..<50 {
            value = AutoBackground.nextShuffle(after: value)
            seen.insert(value)
        }
        #expect(seen.count == 51)
    }
}
