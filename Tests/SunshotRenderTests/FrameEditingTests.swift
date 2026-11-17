import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Frame, token and font editing")
struct FrameEditingTests {
    private static func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 320, height: 200))
        return session
    }

    @Test("[S5-AC1] selecting a frame is one undo entry \"Change Frame\"; re-selecting records nothing")
    func changeFrame() throws {
        var session = try Self.session()
        let count = session.history.undoCount
        session.setFrameKind(.macWindow)
        #expect(session.history.undoCount == count + 1)
        #expect(session.history.undoActionName == "Change Frame")
        session.setFrameKind(.macWindow)
        #expect(session.history.undoCount == count + 1)
        session.undo()
        #expect(session.project.frame.kind == .none)
    }

    @Test("[S5-AC1] every frame has a thumbnail drawn by the same renderer")
    func thumbnails() throws {
        let size = PixelSize(width: 96, height: 64)
        var seen: [[UInt8]] = []
        for kind in FrameKind.allCases {
            let image = try Renderer.renderFrameThumbnail(kind, project: Project(), size: size)
            #expect((image.width, image.height) == (96, 64))
            let bytes = try PixelBuffer(image).bytes
            #expect(!seen.contains(bytes), "\(kind) thumbnail matches another frame")
            seen.append(bytes)
        }
    }

    @Test("[S5-AC9] inline title edit: live updates, commit is one entry, cancel restores without one")
    func inlineTitle() throws {
        var session = try Self.session()
        session.setFrameKind(.macWindow)
        let count = session.history.undoCount
        session.beginTitleEdit()
        for prefix in ["R", "Rel", "Release notes"] { session.setFrameTitle(prefix) }
        #expect(session.project.frame.title == "Release notes")
        session.commitTitleEdit()
        #expect(session.history.undoCount == count + 1)
        #expect(session.history.undoActionName == "Edit Frame Title")

        session.beginTitleEdit()
        session.setFrameTitle("Draft")
        session.cancelTitleEdit(restoring: "Release notes")
        #expect(session.project.frame.title == "Release notes")
        #expect(session.history.undoCount == count + 1)
        session.cancelTitleEdit(restoring: "x")
        #expect(session.project.frame.title == "Release notes")
    }

    @Test("[S5-AC11] a UI-scale slider drag is one undo entry; values are clamped")
    func uiScaleGesture() throws {
        var session = try Self.session()
        session.setFrameKind(.browserWindow)
        let count = session.history.undoCount
        session.beginGesture()
        for value in stride(from: 100.0, through: 260, by: 20) { session.setUIScale(value) }
        session.endGesture(EditorSession.uiScaleActionName)
        #expect(session.project.frame.uiScale == 200)
        #expect(session.history.undoCount == count + 1 && session.history.undoActionName == "Change UI Scale")
        #expect(session.canvasSize == PixelSize(width: 448, height: 416))
    }

    @Test("[S5-AC12] tokens: HEX validated like the backdrop, one entry per change, Reset Colors")
    func colorTokens() throws {
        var session = try Self.session()
        let count = session.history.undoCount
        let short = session.setTokenColor(.foreground, hex: "#12")
        let letters = session.setTokenColor(.foreground, hex: "zzzzzz")
        #expect(!short && !letters)
        #expect(session.history.undoCount == count)
        let magenta = session.setTokenColor(.foreground, hex: "#FF00FF")
        #expect(magenta)
        #expect(session.history.undoActionName == "Change Foreground Color")
        let translucent = session.setTokenColor(.primary, hex: "0a84ff80")
        #expect(translucent)
        #expect(session.project.tokens.colors.primary.hexString == "#0A84FF80")
        #expect(session.history.undoCount == count + 2)
        session.resetColors()
        #expect(session.project.tokens.colors == ColorTokens())
        #expect(session.history.undoActionName == "Reset Colors")
        let afterReset = session.history.undoCount
        session.resetColors()
        #expect(session.history.undoCount == afterReset)
    }

    @Test("[S5-AC15] fonts are stored by PostScript name; a missing font falls back to the system font")
    func fonts() throws {
        var session = try Self.session()
        session.setFrameKind(.macWindow)
        session.setFrameTitle("Release notes")
        let system = try #require(try session.render())
        session.setFont(.text, postScriptName: "Georgia")
        #expect(session.project.tokens.fonts.text == "Georgia")
        #expect(session.history.undoActionName == "Change Text Font")
        let georgia = try #require(try session.render())
        #expect(try PixelBuffer(system).bytes != PixelBuffer(georgia).bytes)

        session.setFont(.text, postScriptName: "NoSuchFont-Regular")
        #expect(!FrameFonts.isAvailable("NoSuchFont-Regular"))
        #expect(FrameFonts.isAvailable("") && FrameFonts.isAvailable("Georgia"))
        let missing = try #require(try session.render())
        #expect(try PixelBuffer(missing).bytes == PixelBuffer(system).bytes)
        session.setFont(.code, postScriptName: "Menlo-Regular")
        #expect(session.history.undoActionName == "Change Code Font")
        session.resetFonts()
        #expect(session.project.tokens.fonts == FontTokens())
    }

    @Test("[S5-AC16] every frame/token/font action is one named entry; undo-all/redo-all reproduce renders")
    func undoRedoAll() throws {
        var session = try Self.session()
        let start = session.history.undoCount
        let first = try #require(try session.render())
        let actions: [(String, (inout EditorSession) -> Void)] = [
            ("Change Frame", { $0.setFrameKind(.browserWindow) }),
            ("Edit Frame Title", { $0.setFrameTitle("Notes") }),
            ("Change UI Scale", { $0.setUIScale(150) }),
            ("Change Foreground Color", { $0.setTokenColor(.foreground, RGBAColor(rgb: 0x112233)) }),
            ("Change Background Color", { $0.setTokenColor(.background, RGBAColor(rgb: 0xEEDDCC)) }),
            ("Change Secondary Color", { $0.setTokenColor(.secondary, RGBAColor(rgb: 0x445566)) }),
            ("Change Primary Color", { $0.setTokenColor(.primary, RGBAColor(rgb: 0xFF8800)) }),
            ("Change Text Font", { $0.setFont(.text, postScriptName: "Georgia") }),
            ("Change Code Font", { $0.setFont(.code, postScriptName: "Menlo-Regular") }),
            ("Change Chrome Appearance", { $0.setChromeAppearance(.dark) }),
            ("Reset Colors", { $0.resetColors() }),
            ("Reset Fonts", { $0.resetFonts() }),
            ("Reset Frame", { $0.resetFrame() }),
        ]
        var models: [Project] = [session.project]
        var renders: [[UInt8]] = [try PixelBuffer(#require(try session.render())).bytes]
        for (name, action) in actions {
            action(&session)
            #expect(session.history.undoActionName == name)
            models.append(session.project)
            renders.append(try PixelBuffer(#require(try session.render())).bytes)
        }
        #expect(session.history.undoCount == start + actions.count)
        for index in stride(from: actions.count - 1, through: 0, by: -1) {
            session.undo()
            #expect(session.project == models[index])
        }
        #expect(try PixelBuffer(#require(try session.render())).bytes == PixelBuffer(first).bytes)
        for index in 1...actions.count {
            session.redo()
            #expect(session.project == models[index])
            #expect(try PixelBuffer(#require(try session.render())).bytes == renders[index], "\(actions[index - 1].0)")
        }
    }
}
