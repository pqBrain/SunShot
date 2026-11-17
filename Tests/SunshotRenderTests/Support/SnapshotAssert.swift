import CoreGraphics
import Foundation
import ImageIO
import SunshotRender
import Testing

/// Pixel-compares `image` against `__Snapshots__/<name>.png`.
///
/// - Missing reference: written, and the test fails (so CI can never silently pass). Re-run to pass.
/// - `SUNSHOT_RECORD_SNAPSHOTS=1`: overwrite references (never honoured when `CI` is set).
/// - On mismatch: `<name>.failure.png` and `<name>.diff.png` are written next to the reference (gitignored).
/// - `tolerance`: per-channel difference ignored; `maxDifferingFraction`: share of pixels allowed to differ.
func assertSnapshot(
    _ image: CGImage,
    named name: String,
    tolerance: UInt8 = 2,
    maxDifferingFraction: Double = 0.001,
    filePath: StaticString = #filePath,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let directory = URL(fileURLWithPath: "\(filePath)")
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__", isDirectory: true)
    let reference = directory.appendingPathComponent("\(name).png")
    let environment = ProcessInfo.processInfo.environment
    let isCI = environment["CI"] != nil
    let record = environment["SUNSHOT_RECORD_SNAPSHOTS"] == "1" && !isCI

    if record || !FileManager.default.fileExists(atPath: reference.path) {
        guard !isCI else {
            Issue.record(
                "Missing snapshot \(name).png (references are never recorded on CI)", sourceLocation: sourceLocation)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ImageCodec.pngData(image).write(to: reference)
        Issue.record("Recorded snapshot \(name).png — review it, then re-run.", sourceLocation: sourceLocation)
        return
    }

    let expected = try ImageCodec.decode(Data(contentsOf: reference))
    let comparison = try PixelComparison(expected: expected, actual: image, tolerance: tolerance)
    if comparison.sizeMismatch || comparison.differingFraction > maxDifferingFraction {
        try ImageCodec.pngData(image).write(to: directory.appendingPathComponent("\(name).failure.png"))
        if let diff = comparison.diffImage {
            try ImageCodec.pngData(diff).write(to: directory.appendingPathComponent("\(name).diff.png"))
        }
        let detail =
            comparison.sizeMismatch
            ? "size \(image.width)x\(image.height) vs reference \(expected.width)x\(expected.height)"
            : String(format: "%.4f%% of pixels differ", comparison.differingFraction * 100)
        Issue.record("Snapshot \(name) mismatch: \(detail)", sourceLocation: sourceLocation)
    }
}

/// RGBA8 pixel buffer of a CGImage, rendered into sRGB premultiplied.
struct PixelBuffer {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn, "could not draw image into pixel buffer")
    }

    /// RGBA at (x, y) with a top-left origin.
    func pixel(x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }
}

struct PixelComparison {
    let sizeMismatch: Bool
    let differingFraction: Double
    let diffImage: CGImage?

    init(expected: CGImage, actual: CGImage, tolerance: UInt8) throws {
        guard expected.width == actual.width, expected.height == actual.height else {
            sizeMismatch = true
            differingFraction = 1
            diffImage = nil
            return
        }
        sizeMismatch = false
        let lhs = try PixelBuffer(expected)
        let rhs = try PixelBuffer(actual)
        var diff = [UInt8](repeating: 0, count: lhs.bytes.count)
        var differing = 0
        for index in stride(from: 0, to: lhs.bytes.count, by: 4) {
            var isDifferent = false
            for channel in 0..<4 {
                let delta = abs(Int(lhs.bytes[index + channel]) - Int(rhs.bytes[index + channel]))
                if delta > Int(tolerance) { isDifferent = true }
            }
            if isDifferent {
                differing += 1
                diff[index] = 255
                diff[index + 3] = 255
            } else {
                diff[index + 3] = 40
            }
        }
        differingFraction = Double(differing) / Double(lhs.width * lhs.height)
        diffImage = Self.makeImage(bytes: diff, width: lhs.width, height: lhs.height)
    }

    private static func makeImage(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
