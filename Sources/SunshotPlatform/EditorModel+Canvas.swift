public import SunshotCore
import SunshotRender

/// Inspector sections the canvas can bring into view.
public enum InspectorSectionID: Hashable, Sendable {
    case backdrop
    case border
}

/// A request to bring `section` into view; `serial` makes repeated clicks on the same region retrigger it.
public struct InspectorFocusRequest: Hashable, Sendable {
    public let section: InspectorSectionID
    public let serial: Int
}

/// S6: direct manipulation in the main preview. `viewWidth` × `viewHeight` is the size the whole canvas is
/// displayed at; points are view points with the origin at the top-left of the displayed canvas.
extension EditorModel {
    /// What lies under a view point: the screenshot (with its frame) or the backdrop. Nil without an image.
    public func canvasRegion(x: Double, y: Double, viewWidth: Double, viewHeight: Double) -> CanvasRegion? {
        guard let size = session.document.imageContentSize, viewWidth > 0, viewHeight > 0 else { return nil }
        let layout = CanvasLayout.compute(contentSize: size, project: project)
        let point = LayoutPoint(
            x: x / viewWidth * Double(layout.canvasSize.width), y: y / viewHeight * Double(layout.canvasSize.height))
        return CanvasHitTest.region(at: point, layout: layout, transform: session.contentTransform)
    }

    /// A click (press without a drag) on the canvas: shows the inspector and asks it to reveal the controls for
    /// what was clicked.
    public func canvasClicked(_ region: CanvasRegion) {
        showsInspector = true
        let section: InspectorSectionID = region == .content ? .border : .backdrop
        inspectorFocus = InspectorFocusRequest(section: section, serial: (inspectorFocus?.serial ?? 0) + 1)
    }

    // MARK: Pinch and twist

    public func beginPinch() {
        guard layout.pinch == nil else { return }
        beginGesture()
        layout.pinch = CanvasPinch(startZoom: session.contentTransform.zoom)
    }

    /// `magnification` is relative to where the pinch started (1 = unchanged).
    public func updatePinch(magnification: Double) {
        guard let pinch = layout.pinch else { return }
        let zoom = pinch.zoom(magnification: magnification)
        perform { $0.setZoom(zoom) }
    }

    public func endPinch() {
        guard layout.pinch != nil else { return }
        layout.pinch = nil
        endGesture(EditorSession.zoomActionName)
    }

    public func beginTwist() {
        guard layout.twist == nil else { return }
        beginGesture()
        layout.twist = CanvasTwist(startRotation: session.contentTransform.rotation)
    }

    /// `degrees` clockwise since the twist started; ⌘ (`snaps` false) turns 45° snapping off.
    public func updateTwist(degrees: Double, snaps: Bool = true) {
        guard let twist = layout.twist else { return }
        let rotation = twist.rotation(angle: degrees, snaps: snaps)
        perform { $0.setRotation(rotation) }
    }

    public func endTwist() {
        guard layout.twist != nil else { return }
        layout.twist = nil
        endGesture(EditorSession.rotateActionName)
    }

    // MARK: Preview size

    /// The view reports the device pixels it can show the preview in; re-renders when that changes the scale.
    public func setPreviewDisplay(width: Double, height: Double) {
        let before = previewScale
        previewDisplayPixels = width > 0 && height > 0 ? (width, height) : nil
        if previewScale != before { Task { await refreshPreview() } }
    }
}
