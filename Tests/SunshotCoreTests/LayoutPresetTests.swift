import Foundation
import Testing

@testable import SunshotCore

@Suite("Layout presets")
struct LayoutPresetTests {
    @Test("[S6-AC13] ≥ 12 bundled presets: unique ids and names, values in range, first is the identity Centered")
    func catalogue() throws {
        let catalog = try LayoutPresetCatalog.load()
        let presets = catalog.presets
        #expect(presets.count >= 12)
        #expect(Set(presets.map(\.id)).count == presets.count)
        #expect(Set(presets.map { $0.name.lowercased() }).count == presets.count)
        let first = try #require(presets.first)
        #expect(first.name == "Centered" && first.transform.isIdentity)
        for preset in presets {
            let t = preset.transform
            #expect(ContentTransform.positionRange.contains(t.x) && ContentTransform.positionRange.contains(t.y))
            #expect(ContentTransform.zoomRange.contains(t.zoom) && t.zoom == t.zoom.rounded())
            #expect(ContentTransform.rotationRange.contains(t.rotation))
            #expect(ContentTransform.tiltRange.contains(t.tiltX) && ContentTransform.tiltRange.contains(t.tiltY))
        }
        #expect(catalog.preset(id: "tabletop")?.name == "Tabletop")
        #expect(catalog.preset(id: nil) == nil && catalog.preset(id: "missing") == nil)
    }

    @Test("[S6-AC13] the catalogue covers flat, corner offset, rotated, left and right tilts and an edge crop")
    func variety() throws {
        let presets = try LayoutPresetCatalog.load().presets
        let transforms = presets.map(\.transform)
        #expect(transforms.contains { $0.isIdentity })
        #expect(transforms.contains { $0.x != 0 && $0.y != 0 && $0.isFlat })
        #expect(transforms.contains { $0.rotation != 0 && $0.isFlat })
        #expect(transforms.contains { $0.tiltY < 0 })
        #expect(transforms.contains { $0.tiltY > 0 })
        // Partly cropped by the canvas edge on the default 1000×600 content.
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 1000, height: 600), project: Project())
        let cropped = transforms.filter {
            ContentProjection(contentRect: layout.contentRect, canvasSize: layout.canvasSize, transform: $0)
                .visibleFraction(canvasSize: layout.canvasSize) < 0.999
        }
        #expect(!cropped.isEmpty)
    }

    @Test("[S6-AC17] every preset keeps ≥ 20 % of the content visible on every content shape and canvas")
    func presetsStayVisible() throws {
        let presets = try LayoutPresetCatalog.load().presets
        let sizes = [
            PixelSize(width: 1000, height: 600), PixelSize(width: 600, height: 1000),
            PixelSize(width: 100, height: 100),
        ]
        let canvases: [CanvasSpec] = [.auto, .ratio(1), .ratio(9.0 / 16)]
        for size in sizes {
            for canvas in canvases {
                let layout = CanvasLayout.compute(contentSize: size, project: Project(canvas: canvas))
                for preset in presets {
                    let projection = ContentProjection(
                        contentRect: layout.contentRect, canvasSize: layout.canvasSize, transform: preset.transform)
                    let visible = projection.visibleFraction(canvasSize: layout.canvasSize)
                    #expect(visible >= 0.2, "\(preset.id) on \(size) \(canvas): \(visible)")
                    #expect(projection.area > 0)
                }
            }
        }
    }

    @Test("[S6-AC13] malformed, empty, duplicate, out-of-range and non-identity-first catalogues are refused")
    func validation() {
        func refuses(_ json: String) -> Bool {
            (try? LayoutPresetCatalog.decode(Data(json.utf8))) == nil
        }
        let centered = #"{"id":"c","name":"Centered","transform":{}}"#
        #expect(refuses("{"))
        #expect(refuses(#"{"presets":[]}"#))
        #expect(refuses(#"{"presets":[{"id":"a","name":"A","transform":{"zoom":110}}]}"#))
        #expect(refuses(#"{"presets":[\#(centered),{"id":"c","name":"B","transform":{}}]}"#))
        #expect(refuses(#"{"presets":[\#(centered),{"id":"d","name":"centered","transform":{}}]}"#))
        #expect(refuses(#"{"presets":[\#(centered),{"id":"d","name":" ","transform":{}}]}"#))
        #expect(refuses(#"{"presets":[\#(centered),{"id":"d","name":"D","transform":{"tiltX":61}}]}"#))
        #expect(refuses(#"{"presets":[\#(centered),{"id":"d","name":"D","transform":{"zoom":120.5}}]}"#))
        #expect(refuses(#"{"presets":[\#(centered),{"id":"d","name":"D","transform":{"x":0.6}}]}"#))
        #expect(!refuses(#"{"presets":[\#(centered),{"id":"d","name":"D","transform":{"rotation":-180}}]}"#))
    }
}
