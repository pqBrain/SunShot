import Foundation
import Testing

@testable import SunshotCore

@Suite("Content transform")
struct ContentTransformTests {
    @Test("[S6-AC1] the default transform is the identity")
    func identity() {
        let transform = ContentTransform()
        #expect(transform == .identity)
        #expect(transform.isIdentity && transform.isFlat)
        #expect((transform.x, transform.y, transform.zoom, transform.rotation) == (0, 0, 100, 0))
        #expect((transform.tiltX, transform.tiltY) == (0, 0))
        #expect(Project().placement == ContentPlacement())
    }

    @Test(
        "[S6-AC6] zoom is a whole percent clamped to 25…400",
        arguments: [
            (24.0, 25.0), (25, 25), (100, 100), (400, 400), (401, 400), (150.4, 150), (.nan, 100), (-.infinity, 100),
        ])
    func zoomClamp(input: Double, stored: Double) {
        #expect(ContentTransform(zoom: input).zoom == stored)
        var transform = ContentTransform()
        transform.zoom = input
        #expect(transform.zoom == stored)
    }

    @Test(
        "[S6-AC7] rotation is normalised into −180…180",
        arguments: [
            (0.0, 0.0), (90, 90), (-90, -90), (180, 180), (-180, -180), (270, -90), (-270, 90), (540, 180), (725, 5),
            (.nan, 0),
        ])
    func rotationNormalised(input: Double, stored: Double) {
        #expect(ContentTransform(rotation: input).rotation == stored)
    }

    @Test("[S6-AC5] [S6-AC9] position and tilt are clamped; non-finite values fall back to identity")
    func clamping() {
        let transform = ContentTransform(x: 0.7, y: -2, tiltX: 75, tiltY: -61)
        #expect((transform.x, transform.y, transform.tiltX, transform.tiltY) == (0.5, -0.5, 60, -60))
        var other = ContentTransform(x: .nan, tiltX: .infinity)
        #expect(other.x == 0 && other.tiltX == 0)
        other.y = 0.25
        other.tiltY = 30
        #expect(other.y == 0.25 && other.tiltY == 30 && !other.isFlat)
    }

    @Test("[S6-AC7] projected bounds: 90° swaps extents, 180° keeps them, 45° of 400×300 is 495×495")
    func rotationBounds() {
        let rect = LayoutRect(x: 364, y: 214, width: 400, height: 300)
        let canvas = PixelSize(width: 1128, height: 728)
        func bounds(_ degrees: Double) -> LayoutRect {
            ContentProjection(contentRect: rect, canvasSize: canvas, transform: ContentTransform(rotation: degrees))
                .bounds
        }
        for (degrees, width, height) in [
            (0.0, 400.0, 300.0), (90, 300, 400), (-90, 300, 400), (180, 400, 300), (45, 495, 495),
        ] {
            let box = bounds(degrees)
            #expect(abs(box.width - width) <= 1 && abs(box.height - height) <= 1, "\(degrees)°: \(box)")
            #expect(abs(box.midX - rect.midX) < 1e-9 && abs(box.midY - rect.midY) < 1e-9)
        }
    }

    @Test("[S6-AC9] tilt Y 30° makes the near (left) edge taller by (d + s) / (d − s) with d = 4 × the longer side")
    func perspectiveRatio() {
        let rect = LayoutRect(x: 0, y: 0, width: 800, height: 600)
        let canvas = PixelSize(width: 800, height: 600)
        let projection = ContentProjection(
            contentRect: rect, canvasSize: canvas, transform: ContentTransform(tiltY: 30))
        let corners = projection.corners
        let left = corners[3].y - corners[0].y
        let right = corners[2].y - corners[1].y
        let lean = 400 * sin(Double.pi / 6)
        #expect(abs(left / right - (3200 + lean) / (3200 - lean)) < 1e-9)
        #expect(projection.perspectiveDistance == 3200)
        // Tilt X 30°: the bottom edge is near (wider) — the top leans away.
        let topAway = ContentProjection(contentRect: rect, canvasSize: canvas, transform: ContentTransform(tiltX: 30))
        let topCorners = topAway.corners
        #expect(topCorners[2].x - topCorners[3].x > topCorners[1].x - topCorners[0].x)
        // Zoom doesn't change the perspective ratio (the camera moves with the content size).
        var zoomed = ContentTransform(zoom: 200, tiltY: 30)
        zoomed.x = 0
        let big = ContentProjection(contentRect: rect, canvasSize: canvas, transform: zoomed).corners
        #expect(abs((big[3].y - big[0].y) / (big[2].y - big[1].y) - left / right) < 1e-9)
    }

    @Test("[S6-AC11] extreme transforms stay finite and visible-fraction maths is safe")
    func extremeFinite() {
        let rect = LayoutRect(x: 64, y: 64, width: 8000, height: 8000)
        let canvas = PixelSize(width: 8128, height: 8128)
        for transform in [
            ContentTransform(zoom: 400, rotation: 180, tiltX: 60, tiltY: 60),
            ContentTransform(x: -0.5, y: 0.5, zoom: 25, rotation: -180, tiltX: -60, tiltY: -60),
        ] {
            let projection = ContentProjection(contentRect: rect, canvasSize: canvas, transform: transform)
            #expect(projection.corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            let fraction = projection.visibleFraction(canvasSize: canvas)
            #expect(fraction.isFinite && fraction > 0 && fraction <= 1)
        }
        let empty = ContentProjection(
            contentRect: LayoutRect(x: 0, y: 0, width: 0, height: .nan), canvasSize: canvas, transform: .identity)
        #expect(empty.visibleFraction(canvasSize: canvas) == 0)
        #expect(ContentProjection.bounds(of: []).width == 0)
        #expect(ContentProjection.area(of: []) == 0)
    }

    @Test("[S6-AC17] visible fraction: centred content is fully visible, content half off the canvas is half visible")
    func visibleFraction() {
        let rect = LayoutRect(x: 50, y: 50, width: 100, height: 100)
        let canvas = PixelSize(width: 200, height: 200)
        let centred = ContentProjection(contentRect: rect, canvasSize: canvas, transform: .identity)
        #expect(abs(centred.visibleFraction(canvasSize: canvas) - 1) < 1e-9)
        let edge = ContentProjection(contentRect: rect, canvasSize: canvas, transform: ContentTransform(x: 0.5))
        #expect(abs(edge.visibleFraction(canvasSize: canvas) - 0.5) < 1e-9)
        let corner = ContentProjection(
            contentRect: rect, canvasSize: canvas, transform: ContentTransform(x: 0.5, y: -0.5))
        #expect(abs(corner.visibleFraction(canvasSize: canvas) - 0.25) < 1e-9)
    }

    @Test("[S6-AC16] interpolation eases between transforms, takes the short way round and ends exactly")
    func interpolation() {
        let from = ContentTransform(x: -0.2, zoom: 100, rotation: 170)
        let to = ContentTransform(x: 0.2, zoom: 151, rotation: -170, tiltX: 20)
        let middle = from.interpolated(to: to, t: 0.5)
        #expect(abs(middle.x) < 1e-12)
        #expect(middle.zoom == 125.5)  // not rounded mid-animation
        #expect(abs(abs(middle.rotation) - 180) < 1e-9)  // via 180°, not via 0°
        #expect(middle.tiltX == 10)
        #expect(from.interpolated(to: to, t: 1) == to)
        #expect(from.interpolated(to: to, t: 2) == to)
        #expect(from.interpolated(to: to, t: 0) == from)
        #expect(from.interpolated(to: to, t: -1) == from)
        #expect(from.interpolated(to: to, t: .nan) == to)
        let back = to.interpolated(to: from, t: 0.25)
        #expect(back.rotation < -170 || back.rotation > 170)
        #expect(TransformAnimation.easeInOut(0) == 0 && TransformAnimation.easeInOut(1) == 1)
        #expect(TransformAnimation.easeInOut(0.5) == 0.5)
        #expect(TransformAnimation.easeInOut(0.25) < 0.25 && TransformAnimation.easeInOut(0.75) > 0.75)
        #expect(TransformAnimation.easeInOut(-1) == 0 && TransformAnimation.easeInOut(.nan) == 1)
    }

    @Test("[S6-AC19] transforms and placements round-trip; missing or invalid keys decode to their defaults")
    func coding() throws {
        let placement = ContentPlacement(
            transform: ContentTransform(x: 0.1, y: -0.2, zoom: 140, rotation: -30, tiltX: 12, tiltY: -8),
            layoutPresetID: "tabletop")
        let data = try JSONEncoder().encode(placement)
        #expect(try JSONDecoder().decode(ContentPlacement.self, from: data) == placement)

        let partial = Data(#"{"transform":{"zoom":999,"rotation":"spin","tiltY":20}}"#.utf8)
        let decoded = try JSONDecoder().decode(ContentPlacement.self, from: partial)
        #expect(decoded.transform == ContentTransform(zoom: 400, tiltY: 20))
        #expect(decoded.layoutPresetID == nil)
        #expect(try JSONDecoder().decode(ContentPlacement.self, from: Data("{}".utf8)) == ContentPlacement())

        // A pre-S6 document (no placement key) decodes with the identity placement.
        var project = Project(padding: 20)
        project.placement = placement
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        #expect(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)) == project)
        json.removeValue(forKey: "placement")
        let old = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.placement == ContentPlacement())
        #expect(old.padding == 20)
        #expect(try JSONDecoder().decode(Project.self, from: Data("{}".utf8)) == Project())
    }
}
