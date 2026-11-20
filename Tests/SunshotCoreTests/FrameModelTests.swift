import Foundation
import Testing

@testable import SunshotCore

@Suite("Frames, tokens and chrome palette")
struct FrameModelTests {
    private func project(_ kind: FrameKind, uiScale: Double = 100) -> Project {
        var project = Project()
        project.frame = Frame(kind: kind, uiScale: uiScale)
        return project
    }

    @Test("[S5-AC1] ten frame kinds in picker order")
    func kinds() {
        #expect(
            FrameKind.allCases == [
                .none, .macWindow, .browserWindow, .card, .stack, .stack2, .stack3, .stack4, .thickBorder, .winWindow,
            ])
        #expect(FrameKind.allCases.filter(\.hasTitle) == [.macWindow, .browserWindow, .winWindow])
    }

    @Test("[S5-AC8] mac window at 100 % on 1000×600 Auto: 1128×756, content unscaled below the bar")
    func autoCanvasGrows() {
        let layout = CanvasLayout.compute(
            contentSize: PixelSize(width: 1000, height: 600), project: project(.macWindow))
        #expect(layout.canvasSize == PixelSize(width: 1128, height: 756))
        #expect(layout.contentRect == LayoutRect(x: 64, y: 92, width: 1000, height: 600))
        #expect(layout.frameRect == LayoutRect(x: 64, y: 64, width: 1000, height: 628))
    }

    @Test("[S5-AC8] every frame kind keeps the content unscaled and fully inside the canvas")
    func everyKindFits() {
        let content = PixelSize(width: 1000, height: 600)
        for kind in FrameKind.allCases {
            for scale in [50.0, 100, 200] {
                let project = project(kind, uiScale: scale)
                let layout = CanvasLayout.compute(contentSize: content, project: project)
                let insets = FrameGeometry.insets(for: project.frame)
                let rect = layout.contentRect
                #expect(rect.width == 1000 && rect.height == 600, "\(kind)")
                #expect(rect.x >= 64 && rect.y >= 64, "\(kind)")
                #expect(Double(layout.canvasSize.width) == (1128 + insets.horizontal).rounded(), "\(kind)")
                #expect(Double(layout.canvasSize.height) == (728 + insets.vertical).rounded(), "\(kind)")
            }
        }
        #expect(FrameGeometry.insets(for: Frame(kind: .none)) == .zero)
        let none = CanvasLayout.compute(contentSize: content, project: Project())
        #expect(none.frameRect == none.contentRect)
    }

    @Test("[S5-AC8] exact canvases scale the frame box with the content")
    func exactCanvas() {
        var project = project(.macWindow)
        project.canvas = .exact(PixelSize(width: 564, height: 378))
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 1000, height: 600), project: project)
        #expect(abs(layout.styleScale - 0.5) < 1e-9)
        #expect(abs(layout.contentRect.width - 500) < 1e-9)
        #expect(abs(layout.contentRect.y - layout.frameRect.y - 14) < 1e-9)
    }

    @Test("[S19-AC1] stack 3 and 4 add cards at 12 px steps, shrinking and fading")
    func deepStacks() {
        #expect(FrameMetrics.stackScales == [0.96, 0.92, 0.88, 0.84])
        #expect(FrameMetrics.stackOpacities == [0.7, 0.45, 0.3, 0.18])
        for (kind, count) in [(FrameKind.stack3, 3), (.stack4, 4)] {
            let insets = FrameGeometry.insets(for: Frame(kind: kind))
            #expect(insets.top == 24 + Double(count) * 12)
            let geometry = FrameGeometry(frame: Frame(kind: kind), boxWidth: 848, boxHeight: 548 + insets.top - 24)
            #expect(geometry.backCards.count == count)
            #expect(geometry.backCards.first?.rect.y == geometry.window.y - Double(count) * 12)
        }
    }

    @Test("[S5-AC6] stack cards sit above the front card, inside the frame box, with decreasing opacity")
    func stackGeometry() {
        for kind in [FrameKind.stack, .stack2, .stack3, .stack4] {
            let insets = FrameGeometry.insets(for: Frame(kind: kind))
            let geometry = FrameGeometry(frame: Frame(kind: kind), boxWidth: 848, boxHeight: 548 + insets.top - 24)
            #expect(geometry.backCards.count == [FrameKind.stack: 1, .stack2: 2, .stack3: 3, .stack4: 4][kind])
            for card in geometry.backCards {
                #expect(card.rect.y >= 0 && card.rect.x >= 0)
                #expect(card.rect.x + card.rect.width <= 848)
            }
            #expect(
                geometry.backCards.map(\.opacity)
                    == Array(FrameMetrics.stackOpacities.prefix(geometry.backCards.count)).reversed())
            #expect(geometry.backCards.last?.rect.y == geometry.window.y - 12)
            #expect(geometry.content.x == 24 && geometry.content.y == insets.top)
        }
        let card = FrameGeometry(frame: Frame(kind: .card), boxWidth: 848, boxHeight: 548)
        #expect(card.backCards.isEmpty && card.outerRadiusExtra == 24)
        #expect(FrameGeometry(frame: Frame(kind: .thickBorder), boxWidth: 100, boxHeight: 100).outerRadiusExtra == 14)
    }

    @Test("[S5-AC10] title rules: whitespace renders empty, 120-character limit, newlines become spaces")
    func titleRules() {
        #expect(Frame(title: "").displayTitle == "")
        #expect(Frame(title: "   ").displayTitle == "")
        #expect(Frame(title: String(repeating: "a", count: 500)).title.count == 120)
        #expect(Frame(title: "one\ntwo\r\nthree").title == "one two three")
        var frame = Frame()
        frame.title = "line\nbreak " + String(repeating: "🙂", count: 200)
        #expect(frame.title.hasPrefix("line break "))
        #expect(frame.title.count == 120)
        frame.title = "שלום Release"
        #expect(frame.displayTitle == "שלום Release")
    }

    @Test("[S5-AC11] UI scale is rounded and clamped; chrome scales linearly, content does not")
    func uiScale() {
        let stored = [49, 50, 100, 200, 201, 150.5].map { Frame(uiScale: $0).uiScale }
        #expect(stored == [50, 50, 100, 200, 200, 151])
        var frame = Frame()
        frame.uiScale = .nan
        #expect(frame.uiScale == 100)
        frame.uiScale = 1000
        #expect(frame.uiScale == 200)

        for kind in FrameKind.allCases {
            let base = FrameGeometry.insets(for: Frame(kind: kind, uiScale: 100))
            let double = FrameGeometry.insets(for: Frame(kind: kind, uiScale: 200))
            #expect(double.top == base.top * 2 && double.left == base.left * 2, "\(kind)")
        }
        let small = FrameGeometry(frame: Frame(kind: .macWindow, uiScale: 100), boxWidth: 800, boxHeight: 528)
        let big = FrameGeometry(frame: Frame(kind: .macWindow, uiScale: 200), boxWidth: 800, boxHeight: 556)
        #expect(big.trafficLightsWidth == small.trafficLightsWidth * 2)
        #expect(big.content.width == small.content.width && big.content.height == small.content.height)
        #expect(big.winButtonWidth == small.winButtonWidth * 2)
    }

    @Test("[S5-AC12] colour token defaults come from SunshotDefaults")
    func tokenDefaults() {
        let colors = Project().tokens.colors
        #expect(colors.foreground.hexString == "#1D1D1F" && colors.foreground == SunshotDefaults.foregroundColor)
        #expect(colors.background.hexString == "#FFFFFF" && colors.background == SunshotDefaults.backgroundColor)
        #expect(colors.secondary.hexString == "#6E6E73" && colors.secondary == SunshotDefaults.secondaryColor)
        #expect(colors.primary.hexString == "#0A84FF" && colors.primary == SunshotDefaults.primaryColor)
        var tokens = ColorTokens()
        for token in ColorToken.allCases {
            tokens[token] = .black
            #expect(tokens[token] == .black)
        }
        var fonts = FontTokens()
        fonts[.code] = "Menlo-Regular"
        fonts[.text] = "Georgia"
        #expect(fonts.code == "Menlo-Regular" && fonts[.text] == "Georgia")
    }

    @Test("[S5-AC14] light/dark force their palettes, auto follows Background luminance, titles meet 4.5:1")
    func lightDark() {
        let darkBackground = RGBAColor(rgb: 0x101014)
        for appearance in ChromeAppearance.allCases {
            for background in [darkBackground, RGBAColor.white] {
                let tokens = DesignTokens(colors: ColorTokens(background: background), chromeAppearance: appearance)
                let palette = ChromePalette.resolve(tokens)
                switch appearance {
                case .light: #expect(palette.bar == ChromePalette.light.bar && !palette.isDark)
                case .dark: #expect(palette.bar == ChromePalette.dark.bar && palette.isDark)
                case .auto: #expect(palette.isDark == (background == darkBackground) && palette.bar == background)
                }
                let ratio = RGBAColor.contrast(palette.title, palette.bar)
                #expect(ratio >= 4.5, "\(appearance) on \(background.hexString): \(ratio)")
            }
        }
        #expect(abs(RGBAColor.white.relativeLuminance - 1) < 1e-9)
        #expect(RGBAColor.black.relativeLuminance == 0)
        #expect(abs(RGBAColor.contrast(.black, .white) - 21) < 1e-9)
        // Auto keeps a readable user foreground as is.
        let custom = DesignTokens(
            colors: ColorTokens(foreground: RGBAColor(rgb: 0xFF00FF), background: RGBAColor(rgb: 0x00FF00)))
        #expect(ChromePalette.resolve(custom).title == RGBAColor(rgb: 0xFF00FF))
        #expect(RGBAColor.black.mixed(with: .white, amount: 0.5).red == 0.5)
    }

    @Test("[S5-AC16] documents without frame/token keys decode with defaults; new fields round-trip")
    func tolerantCoding() throws {
        var project = Project()
        project.frame = Frame(kind: .browserWindow, title: "Notes", uiScale: 150)
        project.tokens = DesignTokens(
            colors: ColorTokens(primary: .black), fonts: FontTokens(text: "Georgia", code: "Menlo-Regular"),
            chromeAppearance: .dark)
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data) == project)

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "frame")
        json.removeValue(forKey: "tokens")
        let old = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.frame == Frame() && old.tokens == DesignTokens())
        #expect(old.export == project.export)

        let partial = Data(#"{"frame":{"kind":"hologram","uiScale":999},"tokens":{"chromeAppearance":"sepia"}}"#.utf8)
        let decoded = try JSONDecoder().decode(Project.self, from: partial)
        #expect(decoded.frame.kind == .none && decoded.frame.uiScale == 200)
        #expect(decoded.tokens.chromeAppearance == .auto && decoded.tokens.colors == ColorTokens())
        #expect(decoded.canvas == .auto && decoded.padding == SunshotDefaults.padding)
    }
}
