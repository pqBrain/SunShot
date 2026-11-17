/// S8: Auto backgrounds — soft mesh gradients generated from the content's palette.
///
/// Each suggestion is a `Wallpaper` recipe (base gradient + soft colour fields), so it is drawn by the existing
/// wallpaper renderer at any resolution and saved with the document like any other wallpaper. Suggestions are
/// a pure function of (palette, shuffle): the same inputs always give the same backgrounds.
public enum AutoBackground {
    public static let suggestionCount = 5
    static let idPrefix = "auto-"

    /// Five generated backgrounds. Empty when the palette is empty.
    public static func suggestions(palette: [RGBAColor], shuffle: UInt64) -> [Wallpaper] {
        let colors = palette.map { RGBAColor(red: $0.red, green: $0.green, blue: $0.blue) }
        guard !colors.isEmpty else { return [] }
        let paletteHash = hash(colors)
        return (0..<suggestionCount).map { index in
            var random = SeededRandom(seed: paletteHash ^ (shuffle &* 0x9E37_79B9_7F4A_7C15) &+ UInt64(index))
            let ordered = shuffled(colors, using: &random)
            let toned = ordered.map { tone($0, style: index) }
            let base = GradientSpec(
                kind: index == 1 ? .radial : .linear, angle: (random.next(in: 0...360)).rounded(),
                stops: [
                    GradientStop(position: 0, color: toned[0]),
                    GradientStop(position: 1, color: toned[min(1, toned.count - 1)]),
                ])
            let fieldCount = 5 + Int(random.next() % 4)
            return Wallpaper(
                id: idPrefix + String(paletteHash, radix: 16) + "-\(shuffle)-\(index)",
                name: "Auto \(index + 1)", seed: random.next(), base: base, palette: Array(toned.dropFirst(2)) + toned,
                fieldCount: fieldCount)
        }
    }

    /// The shuffle value after `shuffle` (deterministic, never equal to it).
    public static func nextShuffle(after shuffle: UInt64) -> UInt64 {
        var random = SeededRandom(seed: shuffle)
        let next = random.next()
        return next == shuffle ? next &+ 1 : next
    }

    /// Whether `wallpaper` was generated here (as opposed to Sunshot's wallpaper set).
    public static func isGenerated(_ wallpaper: Wallpaper) -> Bool { wallpaper.id.hasPrefix(idPrefix) }

    /// The five styles: as found, as found (radial), pastel, deep, and mid-tone.
    private static func tone(_ color: RGBAColor, style: Int) -> RGBAColor {
        switch style {
        case 2: color.mixed(with: .white, amount: 0.45)
        case 3: color.mixed(with: .black, amount: 0.4)
        case 4: color.mixed(with: RGBAColor(red: 0.5, green: 0.5, blue: 0.5), amount: 0.15)
        default: color
        }
    }

    private static func shuffled(_ colors: [RGBAColor], using random: inout SeededRandom) -> [RGBAColor] {
        var result = colors
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            let other = Int(random.next() % UInt64(index + 1))
            result.swapAt(index, other)
        }
        return result
    }

    /// FNV-1a over the 8-bit channels, so tiny float differences don't change the arrangement.
    private static func hash(_ colors: [RGBAColor]) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for color in colors {
            for channel in [color.red, color.green, color.blue] {
                value ^= UInt64((channel * 255).rounded())
                value &*= 0x0000_0100_0000_01B3
            }
        }
        return value
    }
}
