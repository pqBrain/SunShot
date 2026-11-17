import Foundation
import Testing

@testable import SunshotCore

/// Values read from a damaged or hand-edited document or theme must never crash layout, export or rendering:
/// decoding goes through the same clamping initialisers as the app, and length maths saturates.
@Suite("Decode hardening")
struct DecodeHardeningTests {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("a decoded pixel size is at least 1 × 1")
    func pixelSizeClamps() throws {
        let size = try Self.decode(PixelSize.self, #"{"width": 0, "height": -5}"#)
        #expect(size == PixelSize(width: 1, height: 1))
        let roundTrip = try Self.decode(PixelSize.self, String(decoding: JSONEncoder().encode(size), as: UTF8.self))
        #expect(roundTrip == size)
    }

    @Test("decoded colour components are clamped to 0…1")
    func colorClamps() throws {
        let color = try Self.decode(RGBAColor.self, #"{"red": 2, "green": -1, "blue": 0.5, "alpha": 1e300}"#)
        #expect(color == RGBAColor(red: 1, green: 0, blue: 0.5, alpha: 1))
    }

    @Test("a decoded wallpaper's field count is clamped")
    func wallpaperClamps() throws {
        let base = String(decoding: try JSONEncoder().encode(SunshotDefaults.gradient), as: UTF8.self)
        func wallpaper(_ count: Int) throws -> Wallpaper {
            try Self.decode(
                Wallpaper.self,
                #"{"id":"w","name":"W","seed":1,"base":\#(base),"palette":[{"red":1,"green":0,"blue":0,"alpha":1}],"fieldCount":\#(count)}"#
            )
        }
        #expect(try wallpaper(-1).fields.isEmpty)
        #expect(try wallpaper(1_000_000_000).fields.count == 16)
    }

    @Test("decoded padding is clamped; a non-finite one keeps the default")
    func paddingClamps() throws {
        #expect(try Self.decode(Project.self, #"{"padding": 1e19}"#).padding == SunshotDefaults.maxPadding)
        #expect(try Self.decode(Project.self, #"{"padding": -40}"#).padding == 0)
    }

    @Test("absurd canvas sizes and ratios saturate instead of trapping")
    func layoutSaturates() {
        let content = PixelSize(width: 400, height: 300)
        let huge = CanvasLayout.compute(
            contentSize: content, project: Project(canvas: .custom(CustomCanvasSize(width: Int.max / 2, height: nil))))
        #expect(huge.canvasSize.width <= Int.maxLayoutLength)
        let thin = CanvasLayout.compute(contentSize: content, project: Project(canvas: .ratio(1e-300)))
        #expect(thin.canvasSize.height <= Int.maxLayoutLength)
        #expect(ExportPlan(canvas: huge.canvasSize, scale: .x2).isTooLarge)
        // 4K/6K scale the long side down to their target, even from an absurd size.
        #expect(!ExportPlan(canvas: PixelSize(width: Int.max, height: 1), scale: .k6).isTooLarge)
        #expect(ExportPlan.scaled(10, by: .nan) == 0)
        #expect(ExportPlan.scaled(10, by: .infinity) == Int.maxLayoutLength)
        #expect(Int(saturatingLength: -3) == 0)
        #expect(Int(saturatingLength: 2.6) == 3)
    }
}
