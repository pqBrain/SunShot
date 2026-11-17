import CoreGraphics
import SunshotCore

/// Draws an S15 screenshot layout into a frame box: the frame silhouette once per slot, back to front, each
/// rotated about its centre. The primary slot shows the main image as laid out; every other screenshot is shown
/// whole — never cropped — at its own aspect, as large as fits in its slot, centred, with the same content height
/// as the main one so the frame chrome matches. Called by `FrameRenderer` inside the shadow layer and the S6
/// transform, so the layout casts one shadow, moves and tilts as one object, and preview and export match.
enum CollageRenderer {
    /// `box` is the local frame box size (origin 0, 0), in unscaled content units.
    static func draw(
        _ image: CGImage, slots: [Int: CGImage], layout: CollageLayout, project: Project, box: CGSize,
        context: CGContext
    ) {
        let fitted = layout.fitted(toWidth: box.width)
        guard let primary = fitted.primary else { return }
        let primaryGeometry = FrameGeometry(
            frame: project.frame, boxWidth: primary.rect.width, boxHeight: primary.rect.height)
        for slot in fitted.slots {
            let rect = slot.rect.cg
            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: CGFloat(slot.rotation * .pi / 180))
            if slot.isPrimary {
                context.translateBy(x: -rect.width / 2, y: -rect.height / 2)
                FrameRenderer.drawSilhouette(
                    image, project: project, size: rect.size, annotations: project.annotations, context: context)
            } else {
                let shown = slots[slot.index] ?? image
                let natural = naturalBox(
                    for: shown, contentHeight: primaryGeometry.content.height, frame: project.frame)
                let factor = fitFactor(natural, in: rect.size)
                context.scaleBy(x: factor, y: factor)
                context.translateBy(x: -natural.width / 2, y: -natural.height / 2)
                FrameRenderer.drawSilhouette(
                    shown, project: project, size: natural, annotations: AnnotationLayer(), context: context)
            }
            context.restoreGState()
        }
    }

    /// The frame box `image` gets when its content is `contentHeight` tall at its own aspect.
    static func naturalBox(for image: CGImage, contentHeight: Double, frame: Frame) -> CGSize {
        let insets = FrameGeometry.insets(for: frame)
        let aspect = image.height > 0 ? Double(image.width) / Double(image.height) : 1
        let height = max(contentHeight, 1)
        return CGSize(width: height * aspect + insets.horizontal, height: height + insets.vertical)
    }

    /// The largest scale at which `size` fits inside `slot` (aspect kept).
    static func fitFactor(_ size: CGSize, in slot: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(slot.width / size.width, slot.height / size.height)
    }
}
