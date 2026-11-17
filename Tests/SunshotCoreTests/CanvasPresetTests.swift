import Foundation
import Testing

@testable import SunshotCore

@Suite("Canvas presets and size input")
struct CanvasPresetTests {
    /// Social / store brand names that must not appear in preset or group names (device platforms are allowed).
    private static let bannedWords: Set<String> = [
        "instagram", "facebook", "twitter", "tiktok", "youtube", "linkedin", "pinterest", "dribbble", "behance",
        "snapchat", "reddit", "threads", "whatsapp", "discord", "mastodon", "bluesky", "google", "chrome", "play",
        "meta", "x",
    ]
    private static let bannedPhrases = ["app store", "web store", "x.com"]

    private let catalog: CanvasPresetCatalog
    init() throws { catalog = try CanvasPresetCatalog.load() }

    @Test("[S4-AC2] bundled JSON: three groups with ≥4 presets each, ≥25 total, valid ids, ratios and names")
    func catalogShape() throws {
        #expect(catalog.groups.map(\.id) == [.general, .social, .store])
        for group in CanvasPresetGroupID.allCases {
            #expect(catalog.presets.filter { $0.group == group }.count >= 4, "\(group)")
        }
        #expect(catalog.presets.count >= 25)
        #expect(Set(catalog.presets.map(\.id)).count == catalog.presets.count)
        #expect(catalog.presets.allSatisfy { $0.ratioW > 0 && $0.ratioH > 0 && !$0.name.isEmpty })
        #expect(!catalog.sources.isEmpty && catalog.sources.allSatisfy { $0.url.hasPrefix("https://") })
    }

    @Test("[S4-AC2] every store preset has pixelW × pixelH matching its ratio within 0.5 %")
    func storeSizes() {
        let store = catalog.presets.filter { $0.group == .store }
        for preset in store {
            guard let size = preset.exactSize else {
                Issue.record("\(preset.id) has no pixel size")
                continue
            }
            let actual = Double(size.width) / Double(size.height)
            #expect(abs(actual / preset.ratio - 1) <= 0.005, "\(preset.id)")
        }
        let expected = ["store.iphone-6-7": PixelSize(width: 1290, height: 2796)]
        for (id, size) in expected { #expect(catalog.preset(id: id)?.exactSize == size) }
    }

    @Test("[S4-AC2] no third-party brand names in preset names; group labels are neutral")
    func unbranded() {
        let names = catalog.presets.map { "\($0.id) \($0.name)".lowercased() }
        for name in names {
            let words = Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            #expect(words.isDisjoint(with: Self.bannedWords), "\(name)")
            #expect(!Self.bannedPhrases.contains { name.contains($0) }, "\(name)")
        }
        #expect(catalog.groups.map(\.name) == ["General", "Social", "App stores"])
    }

    @Test("[S4-AC2] the validator rejects malformed or inconsistent catalogs")
    func validation() throws {
        func json(
            _ presets: String, groups: String = #"[{"id":"general","name":"G"},{"id":"store","name":"S"}]"#
        )
            -> Data
        { Data(#"{"version":1,"groups":\#(groups),"sources":[],"presets":[\#(presets)]}"#.utf8) }
        let good = #"{"id":"a","group":"general","name":"A","ratioW":16,"ratioH":9}"#
        #expect(try CanvasPresetCatalog.decode(json(good)).presets.count == 1)

        let bad: [(String, Data)] = [
            ("malformed", Data("{".utf8)),
            ("duplicate", json("\(good),\(good)")),
            ("empty id", json(#"{"id":"","group":"general","name":"A","ratioW":1,"ratioH":1}"#)),
            ("undeclared group", json(#"{"id":"a","group":"social","name":"A","ratioW":1,"ratioH":1}"#)),
            ("blank name", json(#"{"id":"a","group":"general","name":"  ","ratioW":1,"ratioH":1}"#)),
            ("zero ratio", json(#"{"id":"a","group":"general","name":"A","ratioW":0,"ratioH":1}"#)),
            ("store without size", json(#"{"id":"a","group":"store","name":"A","ratioW":1,"ratioH":1}"#)),
            ("half size", json(#"{"id":"a","group":"general","name":"A","ratioW":1,"ratioH":1,"pixelW":10}"#)),
            (
                "too big",
                json(#"{"id":"a","group":"store","name":"A","ratioW":1,"ratioH":1,"pixelW":20000,"pixelH":20000}"#)
            ),
            (
                "ratio mismatch",
                json(#"{"id":"a","group":"store","name":"A","ratioW":16,"ratioH":9,"pixelW":1000,"pixelH":1000}"#)
            ),
        ]
        for (label, data) in bad {
            #expect(throws: CanvasPresetCatalogError.self, "\(label)") { try CanvasPresetCatalog.decode(data) }
        }
    }

    @Test("[S4-AC3] search is case-insensitive and trimmed over name, group and ratio; empty restores all")
    func search() {
        let square = catalog.search("square").map(\.id)
        #expect(square.contains("general.square") && square.contains("social.square-post"))
        #expect(catalog.search("9:16").contains { $0.ratioLabel == "9:16" })
        #expect(catalog.search("  STORY ").map(\.name) == ["Story / vertical video"])
        #expect(catalog.search("zzzz").isEmpty && catalog.sections(matching: "zzzz").isEmpty)
        #expect(catalog.search("").count == catalog.presets.count)
        #expect(catalog.search("app stores").allSatisfy { $0.group == .store })
        #expect(catalog.search("1290x2796").map(\.id) == ["store.iphone-6-7"], "exact sizes with a plain x")
        #expect(catalog.sections(matching: "").map(\.group.id) == [.general, .social, .store])
    }

    @Test("[S4-AC4] 1:1 on 1000×600 content is a 1128 px square; content centred and unscaled")
    func squarePreset() throws {
        let content = PixelSize(width: 1000, height: 600)
        let square = try #require(catalog.preset(id: "general.square"))
        let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .preset(square)))
        #expect(layout.canvasSize == PixelSize(width: 1128, height: 1128))
        #expect(layout.contentRect == LayoutRect(x: 64, y: 264, width: 1000, height: 600))
        #expect(layout.styleScale == 1)
    }

    @Test("[S4-AC4] 16:9, 9:16 and 4:5 keep their ratio within 1 px and always fit the padded content")
    func ratioPresets() {
        let contents = [
            PixelSize(width: 1000, height: 600), PixelSize(width: 300, height: 900), .init(width: 5, height: 5),
        ]
        for (w, h) in [(16.0, 9.0), (9.0, 16.0), (4.0, 5.0)] {
            let preset = CanvasPreset(id: "t", group: .general, name: "T", ratioW: w, ratioH: h)
            for content in contents {
                let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .preset(preset)))
                let size = layout.canvasSize
                #expect(abs(Double(size.height) * w / h - Double(size.width)) <= 1, "\(w):\(h) \(content)")
                #expect(size.width >= content.width + 128 && size.height >= content.height + 128)
                #expect(layout.contentRect.width == Double(content.width))
            }
        }
    }

    @Test("[S4-AC5] store presets keep their exact size; padded content scales uniformly to fit")
    func exactPresetLayout() {
        let content = PixelSize(width: 1000, height: 600)
        for preset in catalog.presets.filter({ $0.group == .store }) {
            let layout = CanvasLayout.compute(contentSize: content, project: Project(canvas: .preset(preset)))
            #expect(layout.canvasSize == preset.exactSize, "\(preset.id)")
            let rect = layout.contentRect
            let scale = layout.styleScale
            #expect(abs(rect.width / rect.height - 1000.0 / 600) < 1e-9, "aspect kept")
            #expect(rect.x >= 64 * scale - 1e-6 && rect.y >= 64 * scale - 1e-6, "padding kept proportionally")
            #expect(abs(rect.midX - Double(layout.canvasSize.width) / 2) < 1e-6)
        }
    }

    @Test("[S4-AC6] custom side input: 1…16384 accepted, out of range or text rejected, empty = Auto")
    func customInput() {
        #expect(CanvasSideInput.parse("800") == .pixels(800))
        #expect(CanvasSideInput.parse(" 1 ") == .pixels(1) && CanvasSideInput.parse("16384") == .pixels(16384))
        #expect(CanvasSideInput.parse("640 px") == .pixels(640))
        for text in ["0", "-5", "20000", "abc", "12.5", "16385"] { #expect(CanvasSideInput.parse(text) == .invalid) }
        #expect(CanvasSideInput.parse("") == .auto && CanvasSideInput.parse("Auto") == .auto)
        #expect(
            CanvasSideInput.canvas(width: "800", height: "600") == .custom(CustomCanvasSize(width: 800, height: 600)))
        #expect(CanvasSideInput.canvas(width: "1", height: "1") == .custom(CustomCanvasSize(width: 1, height: 1)))
        #expect(CanvasSideInput.canvas(width: "800", height: "") == .custom(CustomCanvasSize(width: 800, height: nil)))
        #expect(CanvasSideInput.canvas(width: "", height: " ") == .auto)
        #expect(CanvasSideInput.canvas(width: "0", height: "100") == nil)
        #expect(CanvasSideInput.canvas(width: "abc", height: "100") == nil)
    }

    @Test("[S4-AC7] custom W 1200 with H Auto follows the Auto ratio: 1200×774")
    func customOneSide() {
        let content = PixelSize(width: 1000, height: 600)
        let width = Project(canvas: .custom(CustomCanvasSize(width: 1200, height: nil)))
        #expect(
            CanvasLayout.compute(contentSize: content, project: width).canvasSize == .init(width: 1200, height: 774))
        let height = Project(canvas: .custom(CustomCanvasSize(width: nil, height: 728)))
        #expect(CanvasLayout.compute(contentSize: content, project: height).canvasSize.width == 1128)
        let neither = Project(canvas: .custom(CustomCanvasSize(width: nil, height: nil)))
        #expect(
            CanvasLayout.compute(contentSize: content, project: neither).canvasSize == .init(width: 1128, height: 728))
    }

    @Test("[S4-AC20] arrow keys move through the grid, stopping at the edges")
    func gridNavigation() {
        #expect(GridNavigation.move(from: nil, .right, count: 10, columns: 4) == 0)
        #expect(GridNavigation.move(from: 0, .right, count: 10, columns: 4) == 1)
        #expect(GridNavigation.move(from: 0, .left, count: 10, columns: 4) == 0)
        #expect(GridNavigation.move(from: 1, .down, count: 10, columns: 4) == 5)
        #expect(GridNavigation.move(from: 7, .down, count: 10, columns: 4) == 7)
        #expect(GridNavigation.move(from: 5, .up, count: 10, columns: 4) == 1)
        #expect(GridNavigation.move(from: 9, .right, count: 10, columns: 4) == 9)
        #expect(GridNavigation.move(from: 42, .left, count: 10, columns: 4) == 0)
        #expect(GridNavigation.move(from: 0, .down, count: 0, columns: 4) == nil)
    }

    @Test("[S4-AC2] labels: whole ratios without decimals, store presets show their exact size")
    func labels() throws {
        #expect(
            CanvasPreset.format(16) == "16" && CanvasPreset.format(1.91) == "1.91"
                && CanvasPreset.format(19.5) == "19.5")
        #expect(try #require(catalog.preset(id: "store.iphone-6-7")).sizeLabel == "1290×2796")
        #expect(try #require(catalog.preset(id: "general.widescreen")).sizeLabel == "16:9")
    }
}
