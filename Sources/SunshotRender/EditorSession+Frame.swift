public import SunshotCore

/// Frame, colour-token, font and chrome edits. Each is one named undo step; edits that change nothing record
/// nothing. Continuous edits (UI-scale slider, live title typing, colour panel) use `beginGesture` / `endGesture`.
extension EditorSession {
    public static let frameKindActionName = "Change Frame"
    public static let frameTitleActionName = "Edit Frame Title"
    public static let uiScaleActionName = "Change UI Scale"
    public static let resetFrameActionName = "Reset Frame"
    public static let chromeAppearanceActionName = "Change Chrome Appearance"
    public static let resetColorsActionName = "Reset Colors"
    public static let resetFontsActionName = "Reset Fonts"

    /// "Change Foreground Color", … — one name per token so the Edit menu says which one.
    public static func tokenActionName(_ token: ColorToken) -> String {
        "Change \(token.rawValue.prefix(1).uppercased() + token.rawValue.dropFirst()) Color"
    }

    public static func fontActionName(_ role: FontRole) -> String {
        role == .text ? "Change Text Font" : "Change Code Font"
    }

    public mutating func setFrameKind(_ kind: FrameKind) {
        editProject(Self.frameKindActionName) { project in
            project.frame.kind = kind
            project.frame.device = nil  // S12: a frame kind replaces a device mockup
        }
    }

    /// Sets the title (sanitised by `Frame`). Inside a gesture (inline editing) it updates live.
    public mutating func setFrameTitle(_ title: String) {
        editProject(Self.frameTitleActionName) { $0.frame.title = title }
    }

    /// Inline title editing: live updates while typing, Return commits one undo entry, Esc restores.
    public mutating func beginTitleEdit() { history.beginGesture() }

    public mutating func commitTitleEdit() { history.endGestureIfChanged(Self.frameTitleActionName) }

    public mutating func cancelTitleEdit(restoring original: String) {
        guard history.isInGesture else { return }
        history.updateGesture(Self.frameTitleActionName) { $0.project.frame.title = original }
        history.endGestureIfChanged(Self.frameTitleActionName)
    }

    /// UI scale in percent; rounded and clamped to 50…200.
    public mutating func setUIScale(_ percent: Double) {
        editProject(Self.uiScaleActionName) { $0.frame.uiScale = percent }
    }

    public mutating func resetFrame() {
        editProject(Self.resetFrameActionName) { $0.frame = Frame() }
    }

    public mutating func setChromeAppearance(_ appearance: ChromeAppearance) {
        editProject(Self.chromeAppearanceActionName) { $0.tokens.chromeAppearance = appearance }
    }

    public mutating func setTokenColor(_ token: ColorToken, _ color: RGBAColor) {
        editProject(Self.tokenActionName(token)) { $0.tokens.colors[token] = color }
    }

    /// Typed HEX, validated like the backdrop colour. Invalid text is rejected (false) without an undo entry.
    @discardableResult
    public mutating func setTokenColor(_ token: ColorToken, hex: String) -> Bool {
        guard let color = RGBAColor(hex: hex) else { return false }
        setTokenColor(token, color)
        return true
    }

    /// Restores the four default colours (no entry when they already are).
    public mutating func resetColors() {
        editProject(Self.resetColorsActionName) { $0.tokens.colors = ColorTokens() }
    }

    /// Stores a font by PostScript name ("" = system font).
    public mutating func setFont(_ role: FontRole, postScriptName: String) {
        editProject(Self.fontActionName(role)) { $0.tokens.fonts[role] = postScriptName }
    }

    public mutating func resetFonts() {
        editProject(Self.resetFontsActionName) { $0.tokens.fonts = FontTokens() }
    }
}
