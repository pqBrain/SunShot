import AppKit
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Palette and appearance")
struct PaletteTests {
    nonisolated private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @Test("[S1-AC19] all UI text meets WCAG AA (≥ 4.5:1) in Light and Dark", arguments: appearances)
    func contrast(name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        let pairs: [(NSColor, NSColor)] = [
            (SunshotPalette.primaryText, SunshotPalette.workspaceBackground),
            (SunshotPalette.primaryText, SunshotPalette.dropZoneFill),
            (SunshotPalette.secondaryText, SunshotPalette.dropZoneFill),
            (SunshotPalette.secondaryText, SunshotPalette.workspaceBackground),
        ]
        for (foreground, background) in pairs {
            let ratio = Contrast.ratio(foreground, on: background, appearance: appearance)
            #expect(ratio >= 4.5, "\(name.rawValue): \(foreground) on \(background) = \(ratio)")
        }
    }

    @Test("[S1-AC19] contrast maths: black on white is 21:1, a colour on itself is 1:1")
    func contrastMaths() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        #expect(abs(Contrast.ratio(.black, on: .white, appearance: aqua) - 21) < 0.01)
        #expect(abs(Contrast.ratio(.gray, on: .gray, appearance: aqua) - 1) < 0.01)
    }

    @Test("[S1-AC19] the exported image does not depend on the app appearance")
    func exportIgnoresAppearance() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 1000, height: 600))
        var outputs: [Data] = []
        for name in Self.appearances {
            let appearance = try #require(NSAppearance(named: name))
            var png = Data()
            try appearance.performAsCurrentDrawingAppearanceThrowing { png = try session.exportPNG() }
            outputs.append(png)
        }
        #expect(outputs[0] == outputs[1])
    }
}

extension NSAppearance {
    func performAsCurrentDrawingAppearanceThrowing(_ body: () throws -> Void) throws {
        var thrown: (any Error)?
        performAsCurrentDrawingAppearance {
            do { try body() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }
}
