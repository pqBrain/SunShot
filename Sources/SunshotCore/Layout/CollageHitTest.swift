import Foundation

/// S15/S16: which screenshot of a screenshot layout is under a canvas point, and where a screenshot sits on the
/// canvas (its outline for the selection chrome). Works through flat content transforms (moved, zoomed, rotated);
/// a tilted layout is not hit-tested.
public enum CollageHitTest {
    /// The layout laid out in the frame box of `layout` (the unscaled units `Renderer` draws it in).
    static func fitted(_ collage: CollageLayout, layout: CanvasLayout) -> (CollageLayout, boxWidth: Double)? {
        let style = layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1
        let boxWidth = layout.frameRect.width / style
        guard boxWidth > 0, layout.frameRect.height > 0 else { return nil }
        return (collage.fitted(toWidth: boxWidth), boxWidth)
    }

    /// The arrangement slot index (front-most first) under `point` (canvas pixels), or nil.
    public static func slotIndex(
        at point: LayoutPoint, layout: CanvasLayout, collage: CollageLayout, transform: ContentTransform
    ) -> Int? {
        guard transform.isFlat, let (fitted, boxWidth) = fitted(collage, layout: layout) else { return nil }
        let quad = CanvasHitTest.quad(layout: layout, transform: transform)
        guard let local = localPoint(point, quad: quad) else { return nil }
        let boxHeight = boxWidth * layout.frameRect.height / layout.frameRect.width
        let x = local.x * boxWidth
        let y = local.y * boxHeight
        for slot in fitted.slots.reversed() {
            let rect = slot.rect
            let centerX = rect.x + rect.width / 2
            let centerY = rect.y + rect.height / 2
            let radians = -slot.rotation * .pi / 180
            let dx = x - centerX
            let dy = y - centerY
            let rx = dx * cos(radians) - dy * sin(radians)
            let ry = dx * sin(radians) + dy * cos(radians)
            if abs(rx) <= rect.width / 2, abs(ry) <= rect.height / 2 { return slot.index }
        }
        return nil
    }

    /// The corners of slot `index` on the canvas (top-left, top-right, bottom-right, bottom-left), or nil.
    public static func outline(
        ofSlot index: Int, layout: CanvasLayout, collage: CollageLayout, transform: ContentTransform
    ) -> [LayoutPoint]? {
        guard transform.isFlat, let (fitted, boxWidth) = fitted(collage, layout: layout),
            let slot = fitted.slots.first(where: { $0.index == index })
        else { return nil }
        let quad = CanvasHitTest.quad(layout: layout, transform: transform)
        guard quad.count == 4 else { return nil }
        let boxHeight = boxWidth * layout.frameRect.height / layout.frameRect.width
        let rect = slot.rect
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2
        let radians = slot.rotation * .pi / 180
        let corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { sx, sy in
            let dx = sx * rect.width / 2
            let dy = sy * rect.height / 2
            let x = centerX + dx * cos(radians) - dy * sin(radians)
            let y = centerY + dx * sin(radians) + dy * cos(radians)
            // Box units to the canvas through the frame box's (parallelogram) quad.
            let u = x / boxWidth
            let v = y / boxHeight
            return LayoutPoint(
                x: quad[0].x + u * (quad[1].x - quad[0].x) + v * (quad[3].x - quad[0].x),
                y: quad[0].y + u * (quad[1].y - quad[0].y) + v * (quad[3].y - quad[0].y))
        }
        return corners
    }

    /// `point` in the frame box's unit square (0…1 across, 0…1 down) for a parallelogram `quad`.
    static func localPoint(_ point: LayoutPoint, quad: [LayoutPoint]) -> LayoutPoint? {
        guard quad.count == 4 else { return nil }
        let ax = quad[1].x - quad[0].x
        let ay = quad[1].y - quad[0].y
        let bx = quad[3].x - quad[0].x
        let by = quad[3].y - quad[0].y
        let determinant = ax * by - ay * bx
        guard determinant != 0, determinant.isFinite else { return nil }
        let px = point.x - quad[0].x
        let py = point.y - quad[0].y
        return LayoutPoint(x: (px * by - py * bx) / determinant, y: (ax * py - ay * px) / determinant)
    }
}
