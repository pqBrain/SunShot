import Foundation
import Testing

@testable import SunshotCore

/// A minimal valid device file as a mutable dictionary, for the rejection tests.
enum DeviceFixture {
    static func part(_ role: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double = 0) -> [String: Any]
    {
        ["role": role, "x": x, "y": y, "width": w, "height": h, "radius": r]
    }

    static func file() -> [String: Any] {
        [
            "finishes": [
                [
                    "id": "graphite", "name": "Graphite", "shell": "#333333", "highlight": "#555555",
                    "edge": "#222222", "bezel": "#000000", "detail": "#444444",
                ]
            ],
            "models": [
                [
                    "id": "phone", "name": "Phone", "category": "phone", "rotatable": true,
                    "recommended": ["width": 100, "height": 200], "captureSizes": [["width": 100, "height": 200]],
                    "parts": [part("shell", 0, 0, 120, 220, r: 10), part("screen", 10, 10, 100, 200, r: 5)],
                ]
            ],
            "arrangements": [["id": "single", "name": "Single", "slots": [["primary": true]]]],
        ]
    }

    static func data(_ file: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: file) }

    static func decode(_ change: (inout [String: Any]) -> Void) throws -> DeviceCatalog {
        var file = file()
        change(&file)
        return try DeviceCatalog.decode(data(file))
    }

    static func setModel(_ file: inout [String: Any], _ key: String, _ value: Any) {
        var models = file["models"] as? [[String: Any]] ?? []
        models[0][key] = value
        file["models"] = models
    }
}

@Suite("Device catalog and geometry")
struct DeviceCatalogTests {
    let catalog: DeviceCatalog

    init() throws { catalog = try DeviceCatalog.load() }

    @Test("[S12-AC1] the bundled catalog has four generic devices, four finishes and six arrangements")
    func bundled() throws {
        #expect(catalog.models.map(\.name) == ["Phone", "Tablet", "Laptop", "Monitor"])
        #expect(catalog.models.map(\.category) == DeviceCategory.allCases)
        #expect(catalog.finishes.map(\.name) == ["Graphite", "Silver", "Sand", "Sage"])
        #expect(
            catalog.arrangements.map(\.name) == [
                "Single", "Pair", "Trio", "Laptop & Phone", "Monitor & Phone", "Tablet & Phone",
            ])
        #expect(catalog.models.map(\.rotatable) == [true, true, false, false])
        for model in catalog.models {
            #expect(model.parts.filter { $0.role == .screen }.count == 1)
            #expect(abs(model.screenAspect / model.recommendedSize.aspectRatio - 1) <= 0.01, "\(model.id)")
            #expect(model.parts.allSatisfy { $0.rect.x >= 0 && $0.rect.y >= 0 }, "normalised")
            #expect(model.captureSizes.contains(model.recommendedSize), "\(model.id)")
        }
        #expect(DeviceCatalog.bundled == catalog)
        #expect(catalog.model(in: .laptop)?.id == "laptop" && catalog.finish("nope") == nil)
        #expect(catalog.arrangements(for: "laptop").map(\.id) == ["single", "pair", "trio", "laptop-phone"])
    }

    @Test("[S12-AC2] invalid device data is rejected")
    func rejectsInvalid() throws {
        _ = try DeviceFixture.decode { _ in }
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            (
                "two screens",
                {
                    DeviceFixture.setModel(
                        &$0, "parts",
                        [DeviceFixture.part("screen", 0, 0, 100, 200), DeviceFixture.part("screen", 0, 0, 100, 200)])
                }
            ),
            ("no screen", { DeviceFixture.setModel(&$0, "parts", [DeviceFixture.part("shell", 0, 0, 100, 200)]) }),
            ("zero size", { DeviceFixture.setModel(&$0, "parts", [DeviceFixture.part("screen", 0, 0, 0, 200)]) }),
            (
                "big radius",
                { DeviceFixture.setModel(&$0, "parts", [DeviceFixture.part("screen", 0, 0, 100, 200, r: 60)]) }
            ),
            ("aspect", { DeviceFixture.setModel(&$0, "recommended", ["width": 100, "height": 100]) }),
            ("bad size", { DeviceFixture.setModel(&$0, "recommended", ["width": 0, "height": 100]) }),
            (
                "bad role",
                { DeviceFixture.setModel(&$0, "parts", [["role": "notch", "x": 0, "y": 0, "width": 1, "height": 1]]) }
            ),
            ("dup model", { $0["models"] = (($0["models"] as? [Any]) ?? []) + (($0["models"] as? [Any]) ?? []) }),
            (
                "no graphite",
                {
                    $0["finishes"] = [
                        [
                            "id": "x", "name": "X", "shell": "#000", "highlight": "#000", "edge": "#000",
                            "bezel": "#000", "detail": "#000",
                        ]
                    ]
                }
            ),
            (
                "bad colour",
                {
                    $0["finishes"] = [
                        [
                            "id": "graphite", "name": "G", "shell": "#00000080", "highlight": "#000", "edge": "#000",
                            "bezel": "#000", "detail": "#000",
                        ]
                    ]
                }
            ),
            ("no primary", { $0["arrangements"] = [["id": "single", "name": "Single", "slots": [["x": 0]]]] }),
            (
                "two primaries",
                {
                    $0["arrangements"] = [
                        ["id": "single", "name": "Single", "slots": [["primary": true], ["primary": true]]]
                    ]
                }
            ),
            (
                "offset primary",
                { $0["arrangements"] = [["id": "single", "name": "Single", "slots": [["primary": true, "x": 0.2]]]] }
            ),
            (
                "unknown model",
                {
                    $0["arrangements"] = [
                        ["id": "single", "name": "Single", "slots": [["primary": true]]],
                        ["id": "pair", "name": "Pair", "slots": [["primary": true], ["model": "watch", "x": 0.5]]],
                    ]
                }
            ),
            (
                "first not single",
                { $0["arrangements"] = [["id": "pair", "name": "Pair", "slots": [["primary": true]]]] }
            ),
            (
                "huge slot",
                {
                    $0["arrangements"] = [
                        ["id": "single", "name": "Single", "slots": [["primary": true]]],
                        ["id": "big", "name": "Big", "slots": [["primary": true], ["height": 5]]],
                    ]
                }
            ),
        ]
        for (name, change) in cases {
            #expect(throws: DeviceCatalogError.self, "\(name)") { try DeviceFixture.decode(change) }
        }
        #expect(throws: DeviceCatalogError.self) { try DeviceCatalog.decode(Data("{".utf8)) }
        #expect(DeviceCatalogError.missingResource != .invalid("x"))
    }

    @Test("[S12-AC3] the device field defaults to nil, is omitted when unset and tolerates unknown values")
    func selectionCoding() throws {
        #expect(Frame().device == nil && Project().frame.device == nil)
        let plain = try String(decoding: JSONEncoder().encode(Project()), as: UTF8.self)
        #expect(!plain.contains("device"))
        var project = Project()
        project.frame.device = DeviceSelection(model: "tablet", finish: "sand", landscape: true, arrangement: "pair")
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded == project)
        let minimal = try JSONDecoder().decode(DeviceSelection.self, from: Data(#"{"model":"phone"}"#.utf8))
        #expect(minimal == DeviceSelection(model: "phone", finish: "graphite", landscape: false, arrangement: "single"))
        // A malformed device is dropped, not fatal; an unknown model decodes but lays out nothing.
        let frame = try JSONDecoder().decode(Frame.self, from: Data(#"{"kind":"card","device":{"finish":1}}"#.utf8))
        #expect(frame.kind == .card && frame.device == nil)
        #expect(DeviceLayout(selection: DeviceSelection(model: "hologram")) == nil)
        #expect(DeviceLayout(selection: DeviceSelection(model: "phone", finish: "chrome")) == nil)
        #expect(DeviceLayout(selection: DeviceSelection(model: "phone", arrangement: "dozen")) == nil)
        var unknown = Project()
        unknown.frame.device = DeviceSelection(model: "hologram")
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 300, height: 200), project: unknown)
        #expect(layout == CanvasLayout.compute(contentSize: PixelSize(width: 300, height: 200), project: Project()))
    }

    @Test("[S12-AC4] content fills the screen 1:1 and other shapes are centre-cropped")
    func screenCrop() throws {
        var project = Project()
        project.frame.device = DeviceSelection(model: "phone")
        let exact = CanvasLayout.compute(contentSize: PixelSize(width: 1080, height: 2340), project: project)
        #expect(exact.contentRect.width == 1080 && exact.contentRect.height == 2340)
        let device = try #require(DeviceLayout(frame: project.frame))
        let wide = device.screenSize(for: PixelSize(width: 1600, height: 1000))
        #expect(abs(wide.width - 1000 * 360 / 780) < 1e-9 && wide.height == 1000)
        let tall = device.screenSize(for: PixelSize(width: 360, height: 1000))
        #expect(tall.width == 360 && abs(tall.height - 780) < 1e-9)
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 1600, height: 1000), project: project)
        #expect(abs(layout.contentRect.width - wide.width) < 1e-9 && layout.styleScale == 1)
    }

    @Test("[S12-AC5] device chrome grows the Auto canvas: screen + chrome + padding")
    func autoCanvas() throws {
        var project = Project()
        project.frame.device = DeviceSelection(model: "phone")
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 1080, height: 2340), project: project)
        #expect(layout.canvasSize == PixelSize(width: 1346, height: 2588))
        let box = FrameGeometry.layoutBox(for: project.frame, contentSize: PixelSize(width: 1080, height: 2340))
        #expect(box.insets == FrameInsets(top: 60, left: 69, bottom: 60, right: 69))
        #expect(layout.contentRect == LayoutRect(x: 64 + 69, y: 64 + 60, width: 1080, height: 2340))
        #expect(layout.frameRect == LayoutRect(x: 64, y: 64, width: 1218, height: 2460))
        for model in catalog.models {
            for arrangement in catalog.arrangements(for: model.id) {
                project.frame.device = DeviceSelection(model: model.id, arrangement: arrangement.id)
                let size = model.recommendedSize
                let computed = CanvasLayout.compute(contentSize: size, project: project)
                let device = try #require(DeviceLayout(frame: project.frame))
                let factor = computed.contentRect.width / (device.primary?.screen.rect.width ?? 1)
                #expect(abs(computed.frameRect.width - device.width * factor) < 1e-6, "\(model.id) \(arrangement.id)")
                #expect(abs(computed.frameRect.height - device.height * factor) < 1e-6)
                #expect(computed.canvasSize.width == Int((device.width * factor + 128).rounded()))
            }
        }
    }

    @Test("[S12-AC8] landscape turns phones and tablets; laptops and monitors stay upright")
    func orientation() throws {
        let portrait = try #require(DeviceLayout(selection: DeviceSelection(model: "tablet")))
        let landscape = try #require(DeviceLayout(selection: DeviceSelection(model: "tablet", landscape: true)))
        #expect(abs(portrait.width - landscape.height) < 1e-9 && abs(portrait.height - landscape.width) < 1e-9)
        #expect(landscape.screenAspect > 1 && portrait.screenAspect < 1)
        let tablet = try #require(catalog.model("tablet"))
        #expect(tablet.rotated().recommendedSize == PixelSize(width: 2752, height: 2064))
        #expect(tablet.oriented(landscape: false) == tablet)
        let laptop = try #require(DeviceLayout(selection: DeviceSelection(model: "laptop")))
        #expect(DeviceLayout(selection: DeviceSelection(model: "laptop", landscape: true)) == laptop)
    }

    @Test("[S12-AC9] arrangements place every device around the primary; fixed combinations force their model")
    func arrangements() throws {
        let trio = try #require(DeviceLayout(selection: DeviceSelection(model: "phone", arrangement: "trio")))
        #expect(trio.devices.count == 3 && trio.devices.last?.isPrimary == true)
        #expect(trio.devices.allSatisfy { $0.modelID == "phone" })
        let single = try #require(DeviceLayout(selection: DeviceSelection(model: "phone")))
        #expect(trio.width > single.width * 2)
        let combo = try #require(DeviceLayout(selection: DeviceSelection(model: "phone", arrangement: "laptop-phone")))
        #expect(combo.devices.map(\.modelID) == ["laptop", "phone"] && combo.primary?.modelID == "laptop")
        // Companions stay upright when the selection is turned; selection-model slots turn with it.
        let turned = try #require(
            DeviceLayout(selection: DeviceSelection(model: "phone", landscape: true, arrangement: "pair")))
        #expect(turned.devices.allSatisfy { $0.screen.rect.width > $0.screen.rect.height })
        let tabletPhone = try #require(
            DeviceLayout(selection: DeviceSelection(model: "tablet", landscape: true, arrangement: "tablet-phone")))
        #expect(tabletPhone.devices[1].screen.rect.width < tabletPhone.devices[1].screen.rect.height)
        #expect(tabletPhone.screenAspect > 1)
        let scaled = trio.scaled(by: 2)
        #expect(scaled.width == trio.width * 2 && scaled.devices[0].unit == trio.devices[0].unit * 2)
        #expect(trio.fitted(toWidth: 100).width == 100)
    }

    @Test(
        "[S12-AC13] device suggestion from media size",
        arguments: [
            (1179, 2556, "phone", false, DeviceSuggestion.Confidence.exact),
            (2752, 2064, "tablet", true, .exact), (3024, 1964, "laptop", false, .exact),
            (1920, 1080, "desktop", false, .exact), (2340, 1080, "phone", true, .exact),
            (393, 852, "phone", false, .aspect), (1600, 1000, "laptop", false, .aspect),
            (1280, 720, "desktop", false, .aspect), (1560, 720, "phone", true, .aspect),
            (750, 1000, "tablet", false, .aspect),
        ])
    func suggestion(
        width: Int, height: Int, model: String, landscape: Bool, confidence: DeviceSuggestion.Confidence
    )
        throws
    {
        let suggestion = try #require(DeviceSuggestion.suggest(for: PixelSize(width: width, height: height)))
        #expect(suggestion.model.id == model && suggestion.landscape == landscape)
        #expect(suggestion.confidence == confidence)
        #expect(
            suggestion.selection(finish: "sand") == DeviceSelection(model: model, finish: "sand", landscape: landscape))
    }

    @Test("[S12-AC13] media that matches no screen gets no suggestion")
    func noSuggestion() {
        for (width, height) in [(1000, 1000), (800, 300), (300, 800), (1100, 900)] {
            #expect(DeviceSuggestion.suggest(for: PixelSize(width: width, height: height)) == nil, "\(width)×\(height)")
        }
        #expect(DeviceSuggestion.suggest(for: PixelSize(width: 1080, height: 2340), catalog: .empty) == nil)
    }
}
