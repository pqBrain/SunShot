public import SunshotCore

/// Border & shadow edits. Each is one named undo step; edits that change nothing record nothing.
extension EditorSession {
    public static let cornerStyleActionName = "Change Corner Style"
    public static let cornerRadiusActionName = "Change Corner Radius"
    public static let shadowStyleActionName = "Change Shadow Style"
    public static let shadowIntensityActionName = "Change Shadow Intensity"
    public static let lightActionName = "Move Light Source"
    public static let resetBorderActionName = "Reset Border"
    public static let resetShadowActionName = "Reset Shadow"

    public var project: Project { document.project }

    public mutating func setCornerStyle(_ style: CornerStyle) {
        editProject(Self.cornerStyleActionName) { $0.border.style = style }
    }

    /// Sets the radius. During a gesture (slider drag) it updates live and becomes one undo step at the end.
    public mutating func setCornerRadius(_ radius: Double) {
        editProject(Self.cornerRadiusActionName) { $0.border.radius = radius }
    }

    /// Typed radius: non-numeric text is rejected (returns false) and the value is kept.
    @discardableResult
    public mutating func setCornerRadius(text: String) -> Bool {
        guard let value = Border.parseRadius(text) else { return false }
        setCornerRadius(value)
        return true
    }

    public mutating func setShadowStyle(_ style: ShadowStyle) {
        editProject(Self.shadowStyleActionName) { $0.shadow.style = style }
    }

    public mutating func setShadowIntensity(_ intensity: ShadowIntensity) {
        editProject(Self.shadowIntensityActionName) { $0.shadow.intensity = intensity }
    }

    /// Moves the light-source handle (unit circle, x right, y down); the shadow falls the opposite way.
    public mutating func setLightPosition(_ position: UnitOffset) {
        editProject(Self.lightActionName) { $0.shadow.setLight(at: position) }
    }

    public mutating func resetBorder() {
        editProject(Self.resetBorderActionName) { $0.border = Border() }
    }

    public mutating func resetShadow() {
        editProject(Self.resetShadowActionName) { $0.shadow = Shadow() }
    }

    // MARK: Gestures (one undo step per drag)

    public mutating func beginGesture() { history.beginGesture() }

    public mutating func endGesture(_ name: String) { history.endGestureIfChanged(name) }

    private mutating func editProject(_ name: String, _ change: (inout Project) -> Void) {
        if history.isInGesture {
            history.updateGesture(name) { change(&$0.project) }
        } else {
            history.applyIfChanged(name) { change(&$0.project) }
        }
    }
}
