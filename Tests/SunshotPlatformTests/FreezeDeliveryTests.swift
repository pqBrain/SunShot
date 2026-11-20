import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Freeze capture delivery", .serialized)
struct FreezeDeliveryTests {
    @Test("[S19-AC5] a frozen capture copied to the styled clipboard carries the default style; raw does not")
    func styledFrozenCopy() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        controller.model.perform { $0.setPadding(64) }
        controller.saveQuickStyle()
        let frozen = try TestImages.solid(width: 400, height: 300)
        let crop = LayoutRect(x: 10, y: 10, width: 200, height: 100)
        try await withPrivatePasteboard { pasteboard in
            #expect(
                await controller.deliverFrozen(
                    frozen, displaySize: (400, 300), crop: crop, marks: [], to: .styledClipboard,
                    pasteboard: pasteboard))
            let styled = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
            #expect(styled.width > 200 && styled.height > 100)
            #expect(
                await controller.deliverFrozen(
                    frozen, displaySize: (400, 300), crop: crop, marks: [], to: .clipboard, pasteboard: pasteboard))
            let raw = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
            #expect(raw.width == 200 && raw.height == 100)
        }
    }
}
