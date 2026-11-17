import Foundation
import Testing

@testable import SunshotCore

@Suite("Export options, plans and file names")
struct ExportOptionsTests {
    private let canvas = PixelSize(width: 1128, height: 728)
    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    /// 2026-11-17 08:19:05 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_903_545)

    private func context(_ scale: ExportScale = .x2, format: ExportFormat = .png) -> FilenameContext {
        FilenameContext(scale: scale, date: now, width: 2256, height: 1456, format: format)
    }

    @Test("[S4-AC11] 1×, 2×, 4K, 6K of 1128×728 → 1128×728, 2256×1456, 3840×2478, 6144×3965")
    func scales() {
        let expected: [ExportScale: (Int, Int)] = [
            .x1: (1128, 728), .x2: (2256, 1456), .k4: (3840, 2478), .k6: (6144, 3965),
        ]
        for (scale, size) in expected {
            let plan = ExportPlan(canvas: canvas, scale: scale)
            #expect((plan.width, plan.height) == size, "\(scale)")
            #expect(!plan.isTooLarge && !plan.isNativeSize)
        }
        let portrait = ExportPlan(canvas: PixelSize(width: 728, height: 1128), scale: .k4)
        #expect((portrait.width, portrait.height) == (2478, 3840), "4K means the long edge, either way round")
        #expect(SunshotDefaults.exportScale == .x2 && SunshotDefaults.exportFormat == .png)
        #expect(ExportOptions() == ExportOptions(format: .png, scale: .x2))
    }

    @Test("[S4-AC5] native (store) sizes ignore the scale choice")
    func nativeSize() {
        let size = PixelSize(width: 1290, height: 2796)
        for scale in ExportScale.allCases {
            let plan = ExportPlan(canvas: size, scale: scale, isNativeSize: true)
            #expect(plan.outputSize == size && plan.renderScale == 1)
        }
    }

    @Test("[S4-AC12] 16384² at 2× or 6K: the 2× plan is too large; at the limit itself export is allowed")
    func tooLarge() {
        let huge = PixelSize(width: 16384, height: 16384)
        #expect(ExportPlan(canvas: huge, scale: .x2).isTooLarge)
        #expect(!ExportPlan(canvas: huge, scale: .x1).isTooLarge)
        #expect(!ExportPlan(canvas: huge, scale: .k6).isTooLarge, "6K scales a huge canvas down to 6144")
        #expect(ExportPlan(canvas: huge, scale: .k6).outputSize == PixelSize(width: 6144, height: 6144))
        #expect(!ExportPlan(canvas: PixelSize(width: 8128, height: 8128), scale: .x2).isTooLarge, "16256 fits")
        #expect(ExportPlan(canvas: PixelSize(width: 8193, height: 10), scale: .x2).isTooLarge)
    }

    @Test("[S4-AC9] formats: display names, extensions and ImageIO type identifiers")
    func formats() {
        #expect(ExportFormat.allCases.map(\.fileExtension) == ["png", "jpg", "heic", "webp"])
        #expect(ExportFormat.webp.typeIdentifier == "org.webmproject.webp")
        #expect(ExportFormat.allCases.filter { !$0.supportsTransparency } == [.jpeg])
    }

    @Test("[S4-AC14] default template: screenshot_2x_sunshot_2026-11-17_08-19-05.png")
    func defaultTemplate() {
        let name = FilenameTemplate.fileName(
            template: SunshotDefaults.filenameTemplate, context: context(), timeZone: utc)
        #expect(name == "screenshot_2x_sunshot_2026-11-17_08-19-05.png")
        #expect(ExportScale.allCases.map(\.token) == ["1x", "2x", "4k", "6k"])
        #expect(FilenameTemplate.unknownTokens(in: SunshotDefaults.filenameTemplate).isEmpty)
    }

    @Test("[S4-AC14] {WIDTH} {HEIGHT} {SCALE} {RANDOM}: output size, scale token, 6 lowercase alphanumerics")
    func tokens() {
        let sized = FilenameTemplate.fileName(
            template: "{WIDTH}x{HEIGHT}@{SCALE}", context: context(.k4), timeZone: utc)
        #expect(sized == "2256x1456@4k.png")
        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        let a = FilenameTemplate.randomToken(using: &first)
        #expect(a == FilenameTemplate.randomToken(using: &second), "deterministic with an injected generator")
        #expect(a.range(of: "^[a-z0-9]{6}$", options: .regularExpression) != nil)
        #expect(a != FilenameTemplate.randomToken(using: &first), "different on each call")
        let random = FilenameTemplate.fileName(template: "{RANDOM}", context: context(), random: { "abc123" })
        #expect(random == "abc123.png")
        let live = Set((0..<5).map { _ in FilenameTemplate.fileName(template: "{RANDOM}", context: context()) })
        #expect(live.count == 5)
    }

    @Test("[S4-AC15] empty, plain, unsafe, unknown, repeated and over-long templates")
    func edgeCases() {
        func name(_ template: String, _ format: ExportFormat = .png) -> String {
            FilenameTemplate.fileName(template: template, context: context(format: format), timeZone: utc)
        }
        #expect(name("") == "screenshot_2x_sunshot_2026-11-17_08-19-05.png")
        #expect(name("   ") == name(""))
        #expect(name("report") == "report.png")
        #expect(name("a/b:c\\d") == "a-b-c-d.png")
        #expect(name("{UNKNOWN}") == "{UNKNOWN}.png")
        #expect(FilenameTemplate.unknownTokens(in: "{UNKNOWN}_{DATE}") == ["UNKNOWN"])
        #expect(name("{DATE}{DATE}") == "2026-11-17_08-19-052026-11-17_08-19-05.png")
        let long = name(String(repeating: "a", count: 400))
        #expect(long == String(repeating: "a", count: 200) + ".png")
        let wide = name(String(repeating: "é", count: 400), .heic)
        #expect(wide.utf8.count <= 255 && wide.hasSuffix(".heic"))
        #expect(name("report", .jpeg) == "report.jpg" && name("report", .webp) == "report.webp")
        #expect(name("{DATE", .png) == "{DATE.png", "an unclosed brace stays literal")
    }

    @Test("[S4-AC16] button title and spoken label follow format, scale and exact size")
    func buttonLabels() {
        #expect(ExportLabel.title(format: .png, scale: .x2, nativeSize: nil) == "Export 2× • PNG")
        #expect(ExportLabel.title(format: .jpeg, scale: .k4, nativeSize: nil) == "Export 4K • JPEG")
        let store = PixelSize(width: 1290, height: 2796)
        #expect(ExportLabel.title(format: .png, scale: .k6, nativeSize: store) == "Export 1290×2796 • PNG")
        #expect(ExportLabel.spoken(format: .png, scale: .x2, nativeSize: nil) == "Export at 2 times as PNG, ⇧⌘E")
        #expect(ExportLabel.spoken(format: .jpeg, scale: .k4, nativeSize: nil) == "Export at 4K as JPEG, ⇧⌘E")
        #expect(
            ExportLabel.spoken(format: .png, scale: .x1, nativeSize: store)
                == "Export at 1290 by 2796 pixels as PNG, ⇧⌘E")
    }

    @Test("[S4-AC8] canvas specs round-trip through the document encoding")
    func coding() throws {
        let preset = CanvasPreset(id: "p", group: .store, name: "P", ratioW: 1, ratioH: 1, pixelW: 512, pixelH: 512)
        let specs: [CanvasSpec] = [
            .auto, .preset(preset), .custom(CustomCanvasSize(width: 800, height: nil)),
            .custom(CustomCanvasSize(width: nil, height: nil)),
        ]
        for spec in specs {
            let project = Project(canvas: spec, export: ExportOptions(format: .heic, scale: .k6))
            let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
            #expect(decoded == project)
        }
        #expect(CanvasSpec.preset(preset).nativeSize == PixelSize(width: 512, height: 512))
        #expect(CanvasSpec.custom(CustomCanvasSize(width: 800, height: 600)).nativeSize == nil)
    }
}

/// SplitMix64, for repeatable `{RANDOM}` tokens in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
