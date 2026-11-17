import Foundation
public import SunshotCore

/// S6: content position, zoom, rotation, tilt and layout presets. Each edit is one named undo step (drags are
/// coalesced with `beginGesture` / `endGesture`); edits that change nothing record nothing. Any manual change
/// clears the layout preset selection; undo restores it with the transform.
extension EditorSession {
    public static let moveContentActionName = "Move Content"
    public static let zoomActionName = "Change Zoom"
    public static let rotateActionName = "Rotate Content"
    public static let tiltActionName = "Tilt Content"
    public static let resetPositionActionName = "Reset Position"

    public static func applyLayoutActionName(_ preset: LayoutPreset) -> String { "Apply Layout \(preset.name)" }

    public var contentTransform: ContentTransform { document.project.placement.transform }
    public var layoutPresetID: String? { document.project.placement.layoutPresetID }

    /// Moves the content centre (normalised canvas units; clamped to ±0.5).
    public mutating func moveContent(x: Double, y: Double) {
        editTransform(Self.moveContentActionName) {
            $0.x = x
            $0.y = y
        }
    }

    /// Zoom in percent (rounded to a whole percent, 25…400).
    public mutating func setZoom(_ zoom: Double) {
        editTransform(Self.zoomActionName) { $0.zoom = zoom }
    }

    /// Typed zoom ("150.4", "150 %"). Returns false (zoom kept, no undo entry) for non-numeric text.
    @discardableResult
    public mutating func setZoom(text: String) -> Bool {
        guard let value = Self.parseNumber(text, unit: "%") else { return false }
        setZoom(value)
        return true
    }

    /// Rotation in degrees; normalised into −180…180.
    public mutating func setRotation(_ degrees: Double) {
        editTransform(Self.rotateActionName) { $0.rotation = degrees }
    }

    /// Typed rotation ("270" → −90). Returns false for non-numeric text.
    @discardableResult
    public mutating func setRotation(text: String) -> Bool {
        guard let value = Self.parseNumber(text, unit: "°") else { return false }
        setRotation(value)
        return true
    }

    /// Tilt in degrees (each −60…60).
    public mutating func setTilt(x: Double, y: Double) {
        editTransform(Self.tiltActionName) {
            $0.tiltX = x
            $0.tiltY = y
        }
    }

    /// Back to the identity transform as one step; no entry when the transform already is the identity.
    public mutating func resetPosition() {
        guard !contentTransform.isIdentity else { return }
        editProject(Self.resetPositionActionName) { $0.placement = ContentPlacement() }
    }

    /// Applies a layout preset: the exact preset transform plus its selection, one step "Apply Layout <name>".
    public mutating func applyLayoutPreset(_ preset: LayoutPreset) {
        editProject(Self.applyLayoutActionName(preset)) {
            $0.placement = ContentPlacement(transform: preset.transform, layoutPresetID: preset.id)
        }
    }

    /// Projected content on the canvas (for snapping and the mini preview), or nil when empty.
    public var contentProjection: ContentProjection? {
        guard let size = document.imageContentSize else { return nil }
        let layout = CanvasLayout.compute(contentSize: size, project: document.project)
        return ContentProjection(
            contentRect: layout.contentRect, canvasSize: layout.canvasSize, transform: contentTransform)
    }

    /// Starts a position drag on a surface of `width` × `height` px, set up with the content's current extent
    /// for edge snapping.
    public func positionDrag(surfaceWidth width: Double, surfaceHeight height: Double) -> PositionDrag {
        var halfX = 0.0
        var halfY = 0.0
        if let projection = contentProjection, let canvas = canvasSize {
            let bounds = projection.bounds
            halfX = bounds.width / 2 / Double(canvas.width)
            halfY = bounds.height / 2 / Double(canvas.height)
        }
        return PositionDrag(
            startX: contentTransform.x, startY: contentTransform.y, surfaceWidth: width, surfaceHeight: height,
            halfExtentX: halfX, halfExtentY: halfY)
    }

    private mutating func editTransform(_ name: String, _ change: (inout ContentTransform) -> Void) {
        editProject(name) { project in
            var transform = project.placement.transform
            change(&transform)
            guard transform != project.placement.transform else { return }
            project.placement = ContentPlacement(transform: transform, layoutPresetID: nil)
        }
    }

    /// Accepts "150", "150.4", " 150 % ", "-90°"; nil for anything else.
    static func parseNumber(_ text: String, unit: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(unit) { trimmed = String(trimmed.dropLast(unit.count)) }
        guard let value = Double(trimmed.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }
}
