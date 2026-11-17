import Foundation
import Testing

@testable import SunshotCore

@Suite("Annotation model")
struct AnnotationModelTests {
    private func point(_ x: Double, _ y: Double) -> AnnotationPoint { AnnotationPoint(x: x, y: y) }

    private func everyKind() -> AnnotationLayer {
        AnnotationLayer(
            items: [
                Annotation(kind: .pen, points: [point(1, 2), point(3, 4), point(5, 1)], lineStyle: .dotted),
                Annotation(kind: .highlighter, points: [point(0, 0), point(10, 0)], lineWidth: 18),
                Annotation(kind: .arrow, points: [point(5, 5), point(50, 40)], color: RGBAColor(rgb: 0x3366E8)),
                Annotation(kind: .rectangle, points: [point(10, 10), point(60, 30)], filled: true, rotation: 30),
                Annotation(
                    kind: .text, points: [point(0, 0), point(80, 30)], text: "Hi\nthere", fontSize: 20,
                    alignment: .center),
                Annotation(kind: .step, points: [point(0, 0), point(40, 40)]),
                Annotation(kind: .redact, points: [point(5, 5), point(25, 25)], redaction: .blur),
                Annotation(kind: .sticker, points: [point(0, 0), point(70, 70)], text: "🚀"),
            ], stepFormat: .letters)
    }

    @Test("[S9-AC2] a project with every annotation kind round-trips through JSON")
    func roundTrip() throws {
        var project = Project()
        project.annotations = everyKind()
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded == project)
        #expect(decoded.annotations.items.count == 8)
    }

    @Test("[S9-AC2] missing key, unknown kinds and missing fields decode tolerantly")
    func tolerantDecoding() throws {
        let plain = try JSONEncoder().encode(Project())
        let text = try #require(String(data: plain, encoding: .utf8))
        #expect(!text.contains("annotation"), "no annotations → encoded exactly as before S9")
        #expect(try JSONDecoder().decode(Project.self, from: plain).annotations.isEmpty)

        let json = """
            {"items": [
              {"kind": "hologram", "points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]},
              {"kind": "arrow", "points": [{"x": 0, "y": 0}, {"x": 9, "y": 9}], "lineStyle": "wavy"},
              {"kind": "rectangle", "points": [{"x": 0, "y": 0}]},
              {"points": []},
              {"kind": "pen", "points": [{"x": 2, "y": 3}], "lineWidth": "thick"}
            ], "stepFormat": "roman"}
            """
        let layer = try JSONDecoder().decode(AnnotationLayer.self, from: Data(json.utf8))
        #expect(layer.items.map(\.kind) == [.arrow, .pen])
        #expect(layer.items[0].lineStyle == .solid)
        #expect(layer.items[0].color == AnnotationDefaults.color)
        #expect(layer.items[1].lineWidth == AnnotationSize.medium.baseWidth)
        #expect(layer.stepFormat == .numbers)
        #expect(try JSONDecoder().decode(AnnotationLayer.self, from: Data("{}".utf8)) == AnnotationLayer())
    }

    @Test("[S9-AC3] an empty layer is stored as nothing, so cleared documents equal untouched ones")
    func emptyLayerNormalised() {
        var project = Project()
        project.annotations.add(Annotation(kind: .pen, points: [point(1, 1)]))
        #expect(project.annotationLayer != nil)
        project.annotations.items.removeAll()
        #expect(project.annotationLayer == nil)
        #expect(project == Project())
    }

    @Test("[S9-AC2] invalid input is sanitised and invalid annotations are not added")
    func sanitising() {
        let odd = Annotation(
            kind: .text, points: [point(.nan, .infinity)], lineWidth: -3, rotation: .infinity, fontSize: .nan)
        #expect(odd.points[0] == point(0, 0))
        #expect(odd.lineWidth == 0.5)
        #expect(odd.rotation == 0)
        #expect(odd.fontSize == 24)
        #expect(!odd.isValid)
        var layer = AnnotationLayer()
        layer.add(odd)
        #expect(layer.isEmpty)
        #expect(Annotation(kind: .arrow, points: [point(1, 1)], lineWidth: .nan).lineWidth == 6)
    }

    @Test("[S9-AC12] steps number themselves in z-order and renumber after a delete; letters format")
    func stepNumbering() {
        let steps = (0..<3).map {
            Annotation(kind: .step, points: [point(Double($0) * 50, 0), point(Double($0) * 50 + 40, 40)])
        }
        var layer = AnnotationLayer(items: [Annotation(kind: .pen, points: [point(0, 0)])] + steps)
        #expect(steps.map { layer.stepLabel(for: $0.id) } == ["1", "2", "3"])
        layer.remove([steps[1].id])
        #expect(layer.stepLabel(for: steps[2].id) == "2")
        #expect(layer.stepLabel(for: steps[1].id) == nil)
        layer.stepFormat = .letters
        #expect(layer.stepLabel(for: steps[0].id) == "A")
        #expect(StepFormat.letters.label(25) == "Z")
        #expect(StepFormat.letters.label(26) == "AA")
        #expect(StepFormat.letters.label(27) == "AB")
        #expect(StepFormat.numbers.label(9) == "10")
    }

    @Test("[S9-AC15] palette, sizes and shortcuts")
    func paletteAndSizes() {
        #expect(AnnotationDefaults.palette.count == 20)
        #expect(Set(AnnotationDefaults.palette.map(\.color)).count == 20)
        #expect(AnnotationDefaults.palette.prefix(5).map(\.name) == ["White", "Silver", "Grey", "Graphite", "Black"])
        #expect(AnnotationSize.allCases.map(\.baseWidth) == [3, 6, 12])
        #expect(AnnotationSize.medium.lineWidth(contentLongEdge: 800) == 6)
        #expect(AnnotationSize.medium.lineWidth(contentLongEdge: 3000) == 18)
        #expect(AnnotationSize.medium.lineWidth(contentLongEdge: .nan) == 6)
        #expect(AnnotationSize.small.stepped(by: -1) == .small)
        #expect(AnnotationSize.small.stepped(by: 1) == .medium)
        #expect(AnnotationSize.medium.stepped(by: 1) == .large)
        #expect(AnnotationSize.large.stepped(by: 1) == .large)
        let style = AnnotationStyle()
        #expect(style.lineWidth(for: .highlighter, longEdge: 1000) == 18)
        #expect(style.fontSize(longEdge: 1000) == 24)
        #expect(style.stepDiameter(longEdge: 1000) == 48)
        #expect(style.stickerSize(longEdge: 1000) == 72)
        #expect(AnnotationDefaults.stickers.count == 24)
    }

    @Test("[S9-AC1] every tool but the sticker has a unique single-letter shortcut")
    func toolShortcuts() {
        let keys = AnnotationTool.allCases.compactMap(\.shortcut)
        #expect(keys == ["v", "p", "h", "e", "a", "r", "t", "s", "b"])
        #expect(AnnotationTool.forShortcut("P") == .pen)
        #expect(AnnotationTool.forShortcut("b") == .redact)
        #expect(AnnotationTool.forShortcut("z") == nil)
        #expect(AnnotationTool.sticker.shortcut == nil)
        #expect(AnnotationTool.select.kind == nil)
        #expect(AnnotationTool.eraser.kind == nil)
        #expect(AnnotationTool.allCases.compactMap(\.kind).count == AnnotationKind.allCases.count)
        #expect(
            AnnotationKind.allCases.map(AnnotationAction.add) == [
                "Draw", "Highlight", "Add Arrow", "Add Rectangle", "Add Text", "Add Step", "Add Redaction",
                "Add Sticker",
            ])
    }

    @Test("[S9-AC11] text boxes are estimated from the text and refit when edited")
    func textBoxes() {
        let size = TextMetrics.estimatedSize(of: "abcd\nab", fontSize: 20)
        #expect(abs(size.width - (4 * 12 + 4)) < 1e-9)
        #expect(size.height == 50)
        #expect(TextMetrics.estimatedSize(of: "", fontSize: 10).width == 10)
        let text = Annotation.make(
            .text, from: point(10, 20), to: point(10, 20), style: AnnotationStyle(alignment: .right), longEdge: 1000,
            text: "Hi")
        #expect(text.bounds.x == 10)
        #expect(text.bounds.y == 20)
        #expect(text.fontSize == 24)
        #expect(text.alignment == .right)
        let edited = text.withText("Longer text")
        #expect(edited.bounds.width > text.bounds.width)
        #expect(edited.bounds.x == 10)
        let pen = Annotation(kind: .pen, points: [point(0, 0)])
        #expect(pen.withText("x").points == pen.points)
    }

    @Test("[S9-AC14] steps and stickers are placed centred on the click, sized by the size setting")
    func placement() {
        let style = AnnotationStyle(size: .large, sticker: "🔥")
        let sticker = Annotation.make(.sticker, from: point(100, 100), to: point(100, 100), style: style, longEdge: 500)
        #expect(sticker.text == "🔥")
        #expect(sticker.bounds.width == 144)
        #expect(sticker.center == point(100, 100))
        let step = Annotation.make(.step, from: point(50, 50), to: point(50, 50), style: style, longEdge: 500)
        #expect(step.bounds.width == 84)
        let dot = Annotation.make(.pen, from: point(1, 1), to: point(1, 1), style: style, longEdge: 500)
        #expect(dot.points.count == 1)
        let line = Annotation.make(.highlighter, from: point(1, 1), to: point(9, 1), style: style, longEdge: 500)
        #expect(line.points.count == 2)
        #expect(line.lineWidth == 36)
    }
}
