import Foundation

/// One screenshot of a laid-out screenshot layout: its unrotated box in layout units and its rotation about the
/// box centre.
public struct PlacedCollageSlot: Hashable, Sendable {
    /// Index into the arrangement's slots (and the document's slot images).
    public let index: Int
    /// The unrotated slot box (the frame box of that screenshot).
    public let rect: LayoutRect
    /// Degrees, positive = clockwise in the top-left-origin layout space.
    public let rotation: Double
    public let isPrimary: Bool

    func scaled(by factor: Double) -> PlacedCollageSlot {
        PlacedCollageSlot(
            index: index,
            rect: LayoutRect(
                x: rect.x * factor, y: rect.y * factor, width: rect.width * factor, height: rect.height * factor),
            rotation: rotation, isPrimary: isPrimary)
    }
}

/// Where every screenshot of a screenshot layout goes (S15), in layout units with the bounding box at 0, 0.
///
/// The primary slot is the frame box the canvas lays out (at the same size); the other slots are laid out around
/// it and become frame insets, so a layout grows an Auto canvas like S5 chrome and never scales the content.
public struct CollageLayout: Hashable, Sendable {
    public let width: Double
    public let height: Double
    /// Back to front.
    public let slots: [PlacedCollageSlot]

    /// `boxWidth` × `boxHeight` is the primary frame box (content plus frame chrome).
    public init(arrangement: CollageArrangement, boxWidth: Double, boxHeight: Double) {
        var placed: [PlacedCollageSlot] = []
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for (index, slot) in arrangement.slots.enumerated() {
            let width = boxWidth * slot.height
            let height = boxHeight * slot.height
            let centerX = slot.centerX * boxWidth
            let centerY = slot.centerY * boxHeight
            let radians = slot.rotation * .pi / 180
            let halfWidth = abs(width / 2 * cos(radians)) + abs(height / 2 * sin(radians))
            let halfHeight = abs(width / 2 * sin(radians)) + abs(height / 2 * cos(radians))
            minX = min(minX, centerX - halfWidth)
            maxX = max(maxX, centerX + halfWidth)
            minY = min(minY, centerY - halfHeight)
            maxY = max(maxY, centerY + halfHeight)
            placed.append(
                PlacedCollageSlot(
                    index: index,
                    rect: LayoutRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height),
                    rotation: slot.rotation, isPrimary: slot.isPrimary))
        }
        guard !placed.isEmpty else {
            self.init(width: boxWidth, height: boxHeight, slots: [])
            return
        }
        self.init(
            width: maxX - minX, height: maxY - minY,
            slots: placed.map { slot in
                PlacedCollageSlot(
                    index: slot.index,
                    rect: LayoutRect(
                        x: slot.rect.x - minX, y: slot.rect.y - minY, width: slot.rect.width,
                        height: slot.rect.height),
                    rotation: slot.rotation, isPrimary: slot.isPrimary)
            })
    }

    /// The screenshot layout of `project` around a primary frame box, or nil when it has none (a device mockup
    /// takes precedence; an unknown id draws no layout).
    public init?(
        project: Project, boxWidth: Double, boxHeight: Double, catalog: CollageCatalog = .bundled
    ) {
        guard project.frame.device == nil, let arrangement = catalog.arrangement(project.collage) else { return nil }
        self.init(arrangement: arrangement, boxWidth: boxWidth, boxHeight: boxHeight)
    }

    private init(width: Double, height: Double, slots: [PlacedCollageSlot]) {
        self.width = width
        self.height = height
        self.slots = slots
    }

    public var primary: PlacedCollageSlot? { slots.first(where: \.isPrimary) }

    /// The space around the primary slot, as frame insets.
    public var insets: FrameInsets {
        guard let box = primary?.rect else { return .zero }
        return FrameInsets(
            top: box.y, left: box.x, bottom: height - box.y - box.height, right: width - box.x - box.width)
    }

    /// The same layout scaled to fill a box `boxWidth` wide (the box has the layout's aspect).
    public func fitted(toWidth boxWidth: Double) -> CollageLayout {
        let factor = width > 0 ? boxWidth / width : 1
        return CollageLayout(width: width * factor, height: height * factor, slots: slots.map { $0.scaled(by: factor) })
    }
}
