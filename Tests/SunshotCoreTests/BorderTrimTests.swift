import Testing

@testable import SunshotCore

/// S15: auto-trim of a solid-colour border around pasted and captured screenshots.
@Suite("Border trim")
struct BorderTrimTests {
    /// A `width`×`height` RGBA image of `border`, with `inner` filling `rect`.
    static func image(
        width: Int, height: Int, border: [UInt8], inner: [UInt8], rect: CropRect?
    ) -> [UInt8] {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let inside = rect.map { x >= $0.x && x < $0.x + $0.width && y >= $0.y && y < $0.y + $0.height } ?? false
                pixels += inside ? inner : border
            }
        }
        return pixels
    }

    static let white: [UInt8] = [240, 240, 244, 255]
    static let dark: [UInt8] = [30, 30, 34, 255]

    @Test("[S15-AC14] a solid opaque border is found on every side")
    func trims() {
        let content = CropRect(x: 12, y: 8, width: 60, height: 40)
        let pixels = Self.image(width: 100, height: 60, border: Self.white, inner: Self.dark, rect: content)
        #expect(BorderTrim.trimRect(rgba: pixels, width: 100, height: 60) == content)
    }

    @Test("[S15-AC14] noise within tolerance and a few stray pixels still count as border")
    func tolerant() {
        let content = CropRect(x: 10, y: 10, width: 80, height: 40)
        var pixels = Self.image(width: 100, height: 60, border: Self.white, inner: Self.dark, rect: content)
        pixels[(2 * 100 + 50) * 4] = 248  // +8 on one channel: still border
        #expect(BorderTrim.trimRect(rgba: pixels, width: 100, height: 60) == content)
        let wide = 400
        var row = Self.image(
            width: wide, height: 60, border: Self.white, inner: Self.dark,
            rect: CropRect(
                x: 10, y: 10, width: 380, height: 40))
        row[(3 * wide + 200) * 4] = 0  // one stray pixel in a 400-pixel row (0.25 %)
        #expect(BorderTrim.trimRect(rgba: row, width: wide, height: 60)?.y == 10)
    }

    @Test("[S15-AC14] transparent margins, mismatched corners, thin or huge borders and tiny images are left alone")
    func leavesAlone() {
        let clear: [UInt8] = [0, 0, 0, 0]
        let content = CropRect(x: 10, y: 10, width: 80, height: 40)
        let transparent = Self.image(width: 100, height: 60, border: clear, inner: Self.dark, rect: content)
        #expect(BorderTrim.trimRect(rgba: transparent, width: 100, height: 60) == nil)

        var corners = Self.image(width: 100, height: 60, border: Self.white, inner: Self.dark, rect: content)
        for offset in 0..<4 { corners[((59 * 100) + 99) * 4 + offset] = Self.dark[offset] }
        #expect(BorderTrim.trimRect(rgba: corners, width: 100, height: 60) == nil)

        let thin = Self.image(
            width: 100, height: 60, border: Self.white, inner: Self.dark,
            rect: CropRect(x: 2, y: 2, width: 96, height: 56))
        #expect(BorderTrim.trimRect(rgba: thin, width: 100, height: 60) == nil)

        let speck = Self.image(
            width: 100, height: 60, border: Self.white, inner: Self.dark,
            rect: CropRect(x: 45, y: 25, width: 10, height: 10))
        #expect(BorderTrim.trimRect(rgba: speck, width: 100, height: 60) == nil)

        let blank = Self.image(width: 100, height: 60, border: Self.white, inner: Self.white, rect: nil)
        #expect(BorderTrim.trimRect(rgba: blank, width: 100, height: 60) == nil)
        #expect(BorderTrim.trimRect(rgba: [], width: 100, height: 60) == nil)
        #expect(BorderTrim.trimRect(rgba: Self.white + Self.white, width: 2, height: 1) == nil)
    }
}
