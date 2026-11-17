public import Foundation
public import SunshotCore
import SunshotRender

/// S6 phase 2: more direct manipulation in the main preview — drag the backdrop for padding, ⇧-drag the screenshot
/// to tilt, drag the corner handle for the radius, double-click to crop, drop an image on the backdrop to use it
/// there. `viewWidth` × `viewHeight` is the size the whole canvas is displayed at.
extension EditorModel {
    private func canvasGeometry(viewWidth: Double, viewHeight: Double) -> (layout: CanvasLayout, quad: [LayoutPoint])? {
        guard let size = session.document.imageContentSize, viewWidth > 0, viewHeight > 0 else { return nil }
        let layout = CanvasLayout.compute(contentSize: size, project: project)
        return (layout, CanvasHitTest.quad(layout: layout, transform: session.contentTransform))
    }

    // MARK: Padding

    /// Press on the backdrop at (`x`, `y`) view points, about to drag.
    public func beginPaddingDrag(x: Double, y: Double, viewWidth: Double, viewHeight: Double) {
        guard layout.paddingDrag == nil, let geometry = canvasGeometry(viewWidth: viewWidth, viewHeight: viewHeight)
        else { return }
        let toView = viewWidth / Double(geometry.layout.canvasSize.width)
        let centre = CanvasHitTest.centre(of: geometry.quad)
        let style = geometry.layout.styleScale > 0 ? geometry.layout.styleScale : 1
        beginGesture()
        layout.paddingDrag = PaddingDrag(
            startPadding: project.padding, pixelsPerPoint: 1 / toView / style,
            pressX: x - centre.x * toView, pressY: y - centre.y * toView)
    }

    public func updatePaddingDrag(translationX dx: Double, translationY dy: Double) {
        guard let drag = layout.paddingDrag else { return }
        let padding = drag.padding(translationX: dx, translationY: dy)
        perform { $0.setPadding(padding) }
    }

    public func endPaddingDrag() {
        guard layout.paddingDrag != nil else { return }
        layout.paddingDrag = nil
        endGesture(EditorSession.paddingActionName)
    }

    // MARK: Tilt

    public func beginTiltDrag() {
        guard layout.tiltDrag == nil else { return }
        beginGesture()
        layout.tiltDrag = TiltDrag(start: session.contentTransform)
    }

    public func updateTiltDrag(translationX dx: Double, translationY dy: Double) {
        guard let drag = layout.tiltDrag else { return }
        let tilt = drag.tilt(translationX: dx, translationY: dy)
        perform { $0.setTilt(x: tilt.tiltX, y: tilt.tiltY) }
    }

    public func endTiltDrag() {
        guard layout.tiltDrag != nil else { return }
        layout.tiltDrag = nil
        endGesture(EditorSession.tiltActionName)
    }

    // MARK: Corner radius

    /// View points per content pixel at the current zoom.
    private func pointsPerPixel(_ geometry: (layout: CanvasLayout, quad: [LayoutPoint]), viewWidth: Double) -> Double {
        let style = geometry.layout.styleScale > 0 ? geometry.layout.styleScale : 1
        return viewWidth / Double(geometry.layout.canvasSize.width) * style * session.contentTransform.scale
    }

    /// Where the corner-radius handle is drawn (view points), or nil when the screenshot is rotated or tilted, or too
    /// small on screen for a handle.
    public func cornerHandlePoint(viewWidth: Double, viewHeight: Double) -> (x: Double, y: Double)? {
        let transform = session.contentTransform
        guard transform.isFlat, transform.rotation == 0,
            let geometry = canvasGeometry(viewWidth: viewWidth, viewHeight: viewHeight)
        else { return nil }
        let toView = viewWidth / Double(geometry.layout.canvasSize.width)
        let corner = geometry.quad[0]
        let width = (geometry.quad[1].x - corner.x) * toView
        let height = (geometry.quad[3].y - corner.y) * toView
        let radius = project.border.style == .sharp ? 0 : project.border.radius
        let inset = CornerRadiusHandle.inset(
            radius: radius, pointsPerPixel: pointsPerPixel(geometry, viewWidth: viewWidth))
        guard width >= inset * 4, height >= inset * 4 else { return nil }
        return (corner.x * toView + inset, corner.y * toView + inset)
    }

    public func beginCornerDrag() {
        guard layout.cornerDragStart == nil else { return }
        beginGesture()
        layout.cornerDragStart = project.border.style == .sharp ? 0 : project.border.radius
    }

    public func updateCornerDrag(
        translationX dx: Double, translationY dy: Double, viewWidth: Double, viewHeight: Double
    ) {
        guard let start = layout.cornerDragStart,
            let geometry = canvasGeometry(viewWidth: viewWidth, viewHeight: viewHeight)
        else { return }
        let radius = CornerRadiusHandle.radius(
            start: start, translationX: dx, translationY: dy,
            pointsPerPixel: pointsPerPixel(geometry, viewWidth: viewWidth))
        perform { session in
            if session.project.border.style == .sharp, radius > 0 { session.setCornerStyle(.smooth) }
            session.setCornerRadius(radius)
        }
    }

    public func endCornerDrag() {
        guard layout.cornerDragStart != nil else { return }
        layout.cornerDragStart = nil
        endGesture(EditorSession.cornerRadiusActionName)
    }

    // MARK: Double-click and drops

    /// Double-click on the screenshot opens Crop (when cropping is possible).
    public func canvasDoubleClicked(_ region: CanvasRegion) {
        guard region == .content, canCrop else { return }
        openCrop()
    }

    /// A drop on the canvas: one image on the backdrop becomes the backdrop image; anything else is imported as
    /// content as usual.
    @discardableResult
    public func importDropped(_ urls: [URL], on region: CanvasRegion?) async -> Bool {
        let images = urls.filter(isSupportedImageFile)
        if region == .backdrop, hasContent, urls.count == 1, images.count == 1 {
            return await importDroppedBackdrop(images)
        }
        return await importDroppedFiles(urls)
    }
}
