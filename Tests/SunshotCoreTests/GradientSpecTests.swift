import Foundation
import Testing

@testable import SunshotCore

@Suite("Gradient model")
struct GradientSpecTests {
    private let black = RGBAColor.black
    private let white = RGBAColor.white

    private func twoStop(_ a: RGBAColor = .black, _ b: RGBAColor = .white) -> GradientSpec {
        GradientSpec(stops: [GradientStop(position: 0, color: a), GradientStop(position: 1, color: b)])
    }

    @Test("[S3-AC8] angles outside 0…360 are normalised (−90 → 270, 450 → 90)")
    func angleNormalisation() {
        var spec = twoStop()
        spec.angle = -90
        #expect(spec.angle == 270)
        spec.angle = 450
        #expect(spec.angle == 90)
        spec.angle = 360
        #expect(spec.angle == 360)
        spec.angle = .nan
        #expect(spec.angle == 0)
        #expect(GradientSpec(angle: -450, stops: spec.stops).angle == 270)
        #expect(GradientSpec.normalizedAngle(720) == 0)
    }

    @Test("[S3-AC10] a new stop takes the interpolated colour; stops stay sorted and clamped")
    func addAndMove() {
        var spec = twoStop()
        let index = spec.addStop(at: 0.5)
        #expect(index == 1)
        let mid = spec.stops[1].color
        #expect(abs(mid.red - 0.5) < 1e-9 && abs(mid.green - 0.5) < 1e-9 && mid.alpha == 1)

        let moved = spec.moveStop(1, to: 0.8)
        #expect(moved == 1 && spec.stops[1].position == 0.8)
        // Past the last stop: re-sorted to the end. Out of range: clamped.
        let toEnd = spec.moveStop(1, to: 1.5)
        #expect(toEnd == 2 && spec.stops.map(\.position) == [0, 1, 1])
        let toStart = spec.moveStop(2, to: -3)
        #expect(toStart == 0 && spec.stops.map(\.position) == [0, 0, 1])
        let unchanged = spec.moveStop(0, to: 0)
        let unknown = spec.moveStop(9, to: 0.5)
        #expect(unchanged == 0 && unknown == 9, "no-op moves keep the index")
        #expect(zip(spec.stops, spec.stops.dropFirst()).allSatisfy { $0.position <= $1.position })
        let infinite = spec.addStop(at: .infinity)
        #expect(infinite != nil)
        #expect(spec.stops.allSatisfy { (0...1).contains($0.position) })
    }

    @Test("[S3-AC10] delete is refused at 2 stops and add at 12; stop colours change by index")
    func limits() {
        var spec = twoStop()
        let deletedAtTwo = spec.deleteStop(0)
        #expect(!spec.canDeleteStop && !deletedAtTwo)
        for step in 1...10 { spec.addStop(at: Double(step) / 11) }
        #expect(spec.stops.count == 12 && !spec.canAddStop)
        let addedAtTwelve = spec.addStop(at: 0.5)
        #expect(addedAtTwelve == nil)
        let deleted = spec.deleteStop(3)
        let deletedUnknown = spec.deleteStop(42)
        #expect(deleted && !deletedUnknown && spec.stops.count == 11)
        spec.setStopColor(0, .clear)
        spec.setStopColor(99, .clear)
        #expect(spec.stops[0].color == .clear && !spec.isOpaque)
        // Normalisation on creation: sorted (stable), truncated to 12, padded to 2.
        let many = (0..<20).map { GradientStop(position: 1 - Double($0) / 20, color: .black) }
        #expect(GradientSpec(stops: many).stops.count == 12)
        #expect(GradientSpec(stops: []).stops.count == 2)
        let single = GradientSpec(stops: [GradientStop(position: 0.3, color: .white)])
        #expect(single.stops.map(\.position) == [0, 1] && single.stops.allSatisfy { $0.color == .white })
        #expect(GradientStop(position: .nan, color: .black).position == 0)
    }

    @Test("[S3-AC11] stops at the same position make a hard edge; same-colour stops are flat")
    func hardEdgeAndFlat() {
        let red = RGBAColor(rgb: 0xFF0000)
        let blue = RGBAColor(rgb: 0x0000FF)
        let edge = GradientSpec(stops: [
            GradientStop(position: 0, color: red), GradientStop(position: 0.5, color: red),
            GradientStop(position: 0.5, color: blue), GradientStop(position: 1, color: blue),
        ])
        #expect(edge.color(at: 0.4999) == red)
        #expect(edge.color(at: 0.5) == blue)
        #expect(edge.color(at: 0.75) == blue)
        let flat = GradientSpec(stops: [
            GradientStop(position: 0.5, color: red), GradientStop(position: 0.5, color: red),
        ])
        #expect([0, 0.25, 0.5, 0.75, 1, .nan].allSatisfy { flat.color(at: $0) == red })
        // Before the first / after the last stop the end colours extend.
        let inset = GradientSpec(stops: [
            GradientStop(position: 0.2, color: red), GradientStop(position: 0.8, color: blue),
        ])
        #expect(inset.color(at: 0) == red && inset.color(at: 1) == blue)
        #expect(inset.widestGapMidpoint == 0.5)
    }

    @Test("[S3-AC11] interpolation is premultiplied: fading to transparent keeps the hue")
    func premultipliedInterpolation() {
        let red = RGBAColor(rgb: 0xFF0000)
        let half = red.interpolated(to: .clear, fraction: 0.5)
        #expect(half.red == 1 && half.green == 0 && abs(half.alpha - 0.5) < 1e-9)
        let clear = RGBAColor.clear.interpolated(to: RGBAColor(red: 0, green: 1, blue: 0, alpha: 0), fraction: 0.5)
        #expect(clear.alpha == 0 && clear.green == 0.5)
        #expect(red.interpolated(to: .white, fraction: .nan) == red)
    }

    @Test("[S3-AC7] gradients round-trip through JSON and are normalised when decoded")
    func coding() throws {
        let json = Data(
            (#"{"kind":"radial","angle":-90,"stops":[{"position":2,"color":{"red":1,"green":1,"blue":1,"alpha":1}},"#
                + #"{"position":0,"color":{"red":0,"green":0,"blue":0,"alpha":1}}]}"#).utf8)
        let spec = try JSONDecoder().decode(GradientSpec.self, from: json)
        #expect(spec.kind == .radial && spec.angle == 270)
        #expect(spec.stops.map(\.position) == [0, 1] && spec.stops[0].color == .black)
        let again = try JSONDecoder().decode(GradientSpec.self, from: JSONEncoder().encode(spec))
        #expect(again == spec)
    }
}
