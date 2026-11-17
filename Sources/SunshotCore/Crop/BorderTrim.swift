/// Auto-trim for pasted and captured screenshots (S15): finds a solid, opaque border of one colour — the backdrop
/// of a copied canvas, a desktop strip around an area capture — so it can be cut off before the image is used.
///
/// The border colour is the four corners' colour, and only when they agree and are opaque: transparent margins
/// (a window capture's rounded corners or shadow) are kept, because transparency is what users want there. A row
/// or column counts as border when nearly all of its pixels match within `tolerance` (JPEG noise, a stray pixel).
public enum BorderTrim {
    /// Largest per-channel difference that still counts as the border colour.
    public static let tolerance = 10
    /// Share of a row or column that must match for it to count as border.
    public static let matchShare = 0.995
    /// Narrower borders are left alone (not worth changing the image).
    public static let minimumTrim = 3
    /// The kept part must be at least this share of each side, so an image that is mostly one colour (a blank
    /// page, a single colour block) is never reduced to a sliver.
    public static let minimumKeptShare = 0.2

    /// The part of an RGBA image (8 bits per channel, rows top to bottom, `width * 4` bytes per row) inside its
    /// solid border, or nil when there is no border worth trimming.
    public static func trimRect(rgba pixels: [UInt8], width: Int, height: Int) -> CropRect? {
        guard width > 2 * minimumTrim, height > 2 * minimumTrim, pixels.count >= width * height * 4 else {
            return nil
        }
        let image = Pixels(bytes: pixels, width: width)
        let corners = [image[0, 0], image[width - 1, 0], image[0, height - 1], image[width - 1, height - 1]]
        let border = corners[0]
        guard border[3] >= 250, corners.allSatisfy({ matches($0, border) }) else { return nil }

        func rowIsBorder(_ y: Int) -> Bool { share(count: width) { matches(image[$0, y], border) } }
        func columnIsBorder(_ x: Int, _ top: Int, _ bottom: Int) -> Bool {
            share(count: bottom - top) { matches(image[x, top + $0], border) }
        }
        var top = 0
        while top < height, rowIsBorder(top) { top += 1 }
        var bottom = height
        while bottom > top, rowIsBorder(bottom - 1) { bottom -= 1 }
        guard bottom > top else { return nil }
        var left = 0
        while left < width, columnIsBorder(left, top, bottom) { left += 1 }
        var right = width
        while right > left, columnIsBorder(right - 1, top, bottom) { right -= 1 }

        let kept = CropRect(x: left, y: top, width: right - left, height: bottom - top)
        guard
            max(top, height - bottom, left, width - right) >= minimumTrim,
            Double(kept.width) >= Double(width) * minimumKeptShare,
            Double(kept.height) >= Double(height) * minimumKeptShare
        else { return nil }
        return kept
    }

    static func matches(_ pixel: [UInt8], _ border: [UInt8]) -> Bool {
        pixel[3] >= 250 && (0..<3).allSatisfy { abs(Int(pixel[$0]) - Int(border[$0])) <= tolerance }
    }

    private static func share(count: Int, _ isMatch: (Int) -> Bool) -> Bool {
        guard count > 0 else { return false }
        let allowed = Int((Double(count) * (1 - matchShare)).rounded(.down))
        var misses = 0
        for index in 0..<count where !isMatch(index) {
            misses += 1
            if misses > allowed { return false }
        }
        return true
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int

        subscript(x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<offset + 4])
        }
    }
}
