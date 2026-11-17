import Foundation
import Testing

@testable import SunshotCore

/// S15: screenshot layout catalog, geometry and slot lists.
@Suite("Screenshot layouts")
struct CollageLayoutTests {
    @Test("[S15-AC1] the bundled screenshot layouts are valid; unknown ids resolve to no layout")
    func catalog() throws {
        let catalog = CollageCatalog.bundled
        try catalog.validate()
        #expect(catalog.arrangements.count >= 6)
        #expect(catalog.arrangement("hologram") == nil)
        #expect(catalog.arrangement(nil) == nil)
        for arrangement in catalog.arrangements {
            #expect(arrangement.slots[arrangement.primaryIndex] == .primary)
        }
    }

    @Test("[S15-AC1] validation rejects bad layouts")
    func invalid() {
        let pair = [CollageSlot.primary, CollageSlot(centerX: 1.6, centerY: 0.5)]
        let bad: [[CollageArrangement]] = [
            [CollageArrangement(id: "a", name: "A", slots: [.primary])],
            [CollageArrangement(id: "a", name: "A", slots: [CollageSlot(centerX: 0, centerY: 0), .primary])]
                + [CollageArrangement(id: "a", name: "B", slots: pair)],
            [CollageArrangement(id: "a", name: "A", slots: pair), CollageArrangement(id: "b", name: "A", slots: pair)],
            [CollageArrangement(id: "", name: "A", slots: pair)],
            [CollageArrangement(id: "a", name: "A", slots: [CollageSlot(centerX: 1, centerY: 1), .primary, .primary])],
            [
                CollageArrangement(
                    id: "a", name: "A", slots: [CollageSlot(centerX: 1, centerY: 1, height: 2), .primary])
            ],
            [
                CollageArrangement(
                    id: "a", name: "A", slots: [CollageSlot(centerX: 1, centerY: 1, rotation: 45), .primary])
            ],
            [CollageArrangement(id: "a", name: "A", slots: [CollageSlot(centerX: 1, centerY: 1)])],
            [CollageArrangement(id: "a", name: "A", slots: Array(repeating: .primary, count: 5))],
        ]
        for arrangements in bad {
            #expect(throws: CollageCatalogError.self) { try CollageCatalog(arrangements: arrangements).validate() }
        }
    }

    @Test("[S15-AC2] side by side: slots keep the box aspect and the insets are everything but the primary box")
    func sideBySide() throws {
        let arrangement = try #require(CollageCatalog.bundled.arrangement("side-by-side"))
        let layout = CollageLayout(arrangement: arrangement, boxWidth: 400, boxHeight: 300)
        #expect(layout.height == 300)
        #expect(abs(layout.width - (1.62 * 400 + 200)) < 1e-9)
        let primary = try #require(layout.primary)
        #expect(primary.rect == LayoutRect(x: 0, y: 0, width: 400, height: 300))
        #expect(layout.insets == FrameInsets(top: 0, left: 0, bottom: 0, right: layout.width - 400))
        let fitted = layout.fitted(toWidth: layout.width / 2)
        #expect(fitted.height == 150)
        #expect(fitted.slots[1].rect.width == 200)
    }

    @Test("[S15-AC2] rotated slots are bounded tightly; smaller slots scale with their height")
    func rotatedBounds() {
        let tilted = CollageArrangement(
            id: "t", name: "T", slots: [CollageSlot(centerX: 0.5, centerY: 0.5, height: 0.5, rotation: 90), .primary])
        let layout = CollageLayout(arrangement: tilted, boxWidth: 400, boxHeight: 100)
        // The rotated slot is 200×50 turned upright: 50 wide, 200 tall, centred on the primary box.
        #expect(abs(layout.height - 200) < 1e-9)
        #expect(abs(layout.width - 400) < 1e-9)
        #expect(layout.slots[0].rect.width == 200 && layout.slots[0].rect.height == 50)
        #expect(abs(layout.insets.top - 50) < 1e-9 && abs(layout.insets.bottom - 50) < 1e-9)
        let empty = CollageLayout(
            arrangement: CollageArrangement(id: "e", name: "E", slots: []), boxWidth: 4, boxHeight: 3)
        #expect(empty.width == 4 && empty.insets == .zero)
        #expect(empty.fitted(toWidth: 8).height == 6)
        #expect(CollageArrangement(id: "e", name: "E", slots: []).primaryIndex == 0)
    }

    @Test("[S15-AC2] the canvas lays out the primary frame box 1:1; a device wins over a layout")
    func canvas() {
        var project = Project()
        project.padding = 0
        project.collage = "row"
        let size = PixelSize(width: 300, height: 200)
        let layout = CanvasLayout.compute(contentSize: size, project: project)
        #expect(layout.contentRect.width == 300 && layout.contentRect.height == 200)
        #expect(layout.canvasSize.width == Int((300 * 3.24).rounded()))
        project.frame.device = DeviceSelection(model: "phone")
        #expect(CollageLayout(project: project, boxWidth: 1, boxHeight: 1) == nil)
    }

    @Test("[S15-AC5] slots come from the device arrangement, else the screenshot layout, else one main slot")
    func slots() {
        var project = Project()
        #expect(project.contentSlots() == [ContentSlot(index: 0, number: 0)])
        #expect(!project.hasMultipleSlots())
        project.collage = "cascade"
        #expect(project.contentSlots().map(\.isPrimary) == [false, false, true])
        #expect(project.contentSlots().map(\.id) == [1, 2, 0])
        project.collage = "row"
        #expect(project.contentSlots().map(\.number) == [0, 1, 2])
        project.frame.device = DeviceSelection(model: "phone", arrangement: "pair")
        #expect(project.contentSlots().count == 2 && project.hasMultipleSlots())
        project.frame.device = DeviceSelection(model: "phone", arrangement: "nope")
        #expect(project.contentSlots().count == 1)
        project.frame.device = nil
        project.collage = "nope"
        #expect(project.contentSlots().count == 1)
    }

    @Test("[S15-AC10] adding a screenshot grows the layout: one → side by side → row → grid, then full")
    func growth() throws {
        let catalog = CollageCatalog.bundled
        #expect(catalog.layout(toFit: 1, from: nil) == nil)
        #expect(catalog.layout(toFit: 2, from: nil)?.id == "side-by-side")
        #expect(catalog.layout(toFit: 3, from: "side-by-side")?.id == "row")
        #expect(catalog.layout(toFit: 3, from: "overlap")?.id == "cascade")
        #expect(catalog.layout(toFit: 4, from: "fan")?.id == "grid")
        #expect(catalog.layout(toFit: 4, from: nil)?.id == "grid")
        #expect(catalog.layout(toFit: 2, from: "fan")?.id == "fan")
        #expect(catalog.layout(toFit: 5, from: "grid") == nil)
        for id in Array(CollageCatalog.growth.keys) + Array(CollageCatalog.growth.values) + [CollageCatalog.startID] {
            #expect(catalog.arrangement(id) != nil)
        }

        var project = Project()
        #expect(project.growing(toFit: 1) == project)
        project = try #require(project.growing(toFit: 2))
        #expect(project.collage == "side-by-side")
        project = try #require(project.growing(toFit: 3))
        #expect(project.collage == "row")
        #expect(project.growing(toFit: 5) == nil)

        // A device grows its arrangement and keeps its model; fixed combinations are never picked.
        var device = Project()
        device.frame.device = DeviceSelection(model: "phone")
        device = try #require(device.growing(toFit: 2))
        #expect(device.frame.device?.arrangement == "pair" && device.frame.device?.model == "phone")
        device = try #require(device.growing(toFit: 3))
        #expect(device.frame.device?.arrangement == "trio")
        #expect(device.growing(toFit: 4) == nil)
        var laptop = Project()
        laptop.frame.device = DeviceSelection(model: "laptop")
        #expect(laptop.growing(toFit: 2)?.frame.device?.arrangement != "laptop-phone")
    }

    @Test("[S15-AC11] removing a screenshot shrinks the layout: grid → row → side by side → none")
    func shrink() {
        let catalog = CollageCatalog.bundled
        #expect(catalog.layout(shrinkingTo: 3, from: "grid")?.id == "row")
        #expect(catalog.layout(shrinkingTo: 2, from: "grid")?.id == "side-by-side")
        #expect(catalog.layout(shrinkingTo: 2, from: "cascade")?.id == "overlap")
        #expect(catalog.layout(shrinkingTo: 2, from: "fan")?.id == "side-by-side")
        #expect(catalog.layout(shrinkingTo: 3, from: "fan")?.id == "fan")
        #expect(catalog.layout(shrinkingTo: 1, from: "row") == nil)
        for id in Array(CollageCatalog.shrink.keys) + Array(CollageCatalog.shrink.values) {
            #expect(catalog.arrangement(id) != nil)
        }
        var project = Project()
        project.collage = "grid"
        #expect(project.shrinking(toFit: 4) == project)
        #expect(project.shrinking(toFit: 2).collage == "side-by-side")
        project.frame.device = DeviceSelection(model: "laptop", arrangement: "laptop-phone")
        #expect(project.shrinking(toFit: 1).frame.device?.arrangement == "single")
        #expect(project.shrinking(toFit: 1).frame.device?.model == "laptop")
    }

    @Test("[S15-AC7] the layout id round-trips through JSON and older documents decode without it")
    func coding() throws {
        var project = Project()
        project.collage = "fan"
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.collage == "fan")
        let old = try JSONDecoder().decode(Project.self, from: Data("{}".utf8))
        #expect(old.collage == nil)
    }
}
