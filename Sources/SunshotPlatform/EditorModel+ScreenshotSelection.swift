public import SunshotCore
import SunshotRender

/// S16: pick one screenshot of a screenshot layout on the canvas, then delete it (Delete key or its × button) or
/// drag it onto another screenshot to swap their places. With nothing picked, a drag moves the whole layout.
extension EditorModel {
    /// The picked screenshot, while it still exists with an image and can be removed.
    public var selectedScreenshot: Int? {
        guard let number = layout.selectedScreenshot, canRemoveScreenshot(number),
            session.contentSlots.contains(where: { $0.number == number })
        else { return nil }
        return number
    }

    /// The screenshot layout as `Renderer` lays it out (nil without one).
    private func collageGeometry() -> (layout: CanvasLayout, collage: CollageLayout)? {
        guard let size = session.document.imageContentSize else { return nil }
        let frameBox = FrameGeometry.layoutBox(for: project.frame, contentSize: size)
        guard
            let collage = CollageLayout(
                project: project, boxWidth: frameBox.width + frameBox.insets.horizontal,
                boxHeight: frameBox.height + frameBox.insets.vertical)
        else { return nil }
        return (CanvasLayout.compute(contentSize: size, project: project), collage)
    }

    /// The screenshot number under (`x`, `y`) view points of a preview `viewWidth` × `viewHeight`, or nil.
    public func screenshotNumber(x: Double, y: Double, viewWidth: Double, viewHeight: Double) -> Int? {
        guard viewWidth > 0, viewHeight > 0, session.contentSlots.count > 1,
            let (layout, collage) = collageGeometry()
        else { return nil }
        let point = LayoutPoint(
            x: x / viewWidth * Double(layout.canvasSize.width), y: y / viewHeight * Double(layout.canvasSize.height))
        guard
            let index = CollageHitTest.slotIndex(
                at: point, layout: layout, collage: collage, transform: session.contentTransform)
        else { return nil }
        return session.contentSlots.first { $0.index == index }?.number
    }

    /// A click on the canvas picks the screenshot under it (one that can be removed), or clears the pick.
    public func pickScreenshot(x: Double, y: Double, viewWidth: Double, viewHeight: Double) {
        let number = screenshotNumber(x: x, y: y, viewWidth: viewWidth, viewHeight: viewHeight)
        layout.selectedScreenshot = number.flatMap { canRemoveScreenshot($0) ? $0 : nil }
    }

    public func clearScreenshotPick() { layout.selectedScreenshot = nil }

    /// Corners of the picked screenshot in view points (top-left, top-right, bottom-right, bottom-left), or nil.
    public func pickedScreenshotOutline(viewWidth: Double, viewHeight: Double) -> [LayoutPoint]? {
        guard let number = selectedScreenshot else { return nil }
        return screenshotOutline(number: number, viewWidth: viewWidth, viewHeight: viewHeight)
    }

    /// Corners of screenshot `number` of the layout in view points, or nil.
    public func screenshotOutline(number: Int, viewWidth: Double, viewHeight: Double) -> [LayoutPoint]? {
        guard viewWidth > 0, viewHeight > 0,
            let slot = session.contentSlots.first(where: { $0.number == number }),
            let (layout, collage) = collageGeometry(),
            let corners = CollageHitTest.outline(
                ofSlot: slot.index, layout: layout, collage: collage, transform: session.contentTransform)
        else { return nil }
        let sx = viewWidth / Double(layout.canvasSize.width)
        let sy = viewHeight / Double(layout.canvasSize.height)
        return corners.map { LayoutPoint(x: $0.x * sx, y: $0.y * sy) }
    }

    /// While the picked screenshot is dragged to (`x`, `y`): the screenshot it would swap places with, or nil.
    public func reorderTarget(x: Double, y: Double, viewWidth: Double, viewHeight: Double) -> Int? {
        guard let picked = selectedScreenshot,
            let target = screenshotNumber(x: x, y: y, viewWidth: viewWidth, viewHeight: viewHeight),
            target != picked
        else { return nil }
        // The main slot can't be left empty: the main screenshot only swaps with one that has an image.
        if picked == 0, session.document.slots[target] == nil { return nil }
        return target
    }

    /// Drop of the picked screenshot at (`x`, `y`): it swaps places with the screenshot there (one undo step
    /// "Move Screenshot") and stays picked in its new place. Returns whether it moved.
    @discardableResult
    public func dropPickedScreenshot(x: Double, y: Double, viewWidth: Double, viewHeight: Double) -> Bool {
        guard let picked = selectedScreenshot,
            let target = reorderTarget(x: x, y: y, viewWidth: viewWidth, viewHeight: viewHeight)
        else { return false }
        moveScreenshot(from: picked, to: target)
        layout.selectedScreenshot = target
        return true
    }

    /// Delete: removes the picked screenshot (one undo step); the layout shrinks to fit. Returns whether it did.
    @discardableResult
    public func deletePickedScreenshot() -> Bool {
        guard let number = selectedScreenshot else { return false }
        layout.selectedScreenshot = nil
        removeScreenshot(at: number)
        return true
    }
}
