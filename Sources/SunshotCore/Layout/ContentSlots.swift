/// One place a screenshot goes (S15): a device of a multi-device arrangement or a screenshot of a screenshot
/// layout. The primary slot always shows the document's main image.
public struct ContentSlot: Hashable, Sendable, Identifiable {
    /// Index into the active arrangement's slots (where it is drawn).
    public let index: Int
    /// The screenshot number: 0 for the main slot, then 1, 2… for the others in arrangement order. It keys the
    /// document's slot images, so they keep their order when a layout grows or changes.
    public let number: Int

    public init(index: Int, number: Int) {
        self.index = index
        self.number = number
    }

    public var isPrimary: Bool { number == 0 }
    public var id: Int { number }

    /// Slots for arrangement slots flagged primary or not, numbered main first, then in order.
    static func numbered(_ primaries: [Bool]) -> [ContentSlot] {
        var next = 1
        return primaries.enumerated().map { index, isPrimary in
            if isPrimary { return ContentSlot(index: index, number: 0) }
            defer { next += 1 }
            return ContentSlot(index: index, number: next)
        }
    }
}

extension Project {
    /// The slots of the active arrangement: the device arrangement when a device is set, else the screenshot
    /// layout. A single device or no layout has one primary slot. Unknown ids give one primary slot.
    public func contentSlots(
        devices: DeviceCatalog = .bundled, collages: CollageCatalog = .bundled
    ) -> [ContentSlot] {
        if let device = frame.device {
            guard let arrangement = devices.arrangement(device.arrangement) else { return [Self.mainSlot] }
            return ContentSlot.numbered(arrangement.slots.map(\.isPrimary))
        }
        guard let collage = collages.arrangement(collage) else { return [Self.mainSlot] }
        return ContentSlot.numbered(collage.slots.map(\.isPrimary))
    }

    /// True when the active arrangement has room for more than one screenshot.
    public func hasMultipleSlots(devices: DeviceCatalog = .bundled, collages: CollageCatalog = .bundled) -> Bool {
        contentSlots(devices: devices, collages: collages).count > 1
    }

    private static let mainSlot = ContentSlot(index: 0, number: 0)

    /// The same style with no more slots than `count` screenshots need (after one is removed): the screenshot
    /// layout shrinks along `CollageCatalog.shrink` (one screenshot = no layout) and a device falls back to the
    /// largest plain arrangement that fits (Single at least).
    public func shrinking(
        toFit count: Int, devices: DeviceCatalog = .bundled, collages: CollageCatalog = .bundled
    ) -> Project {
        if contentSlots(devices: devices, collages: collages).count <= count { return self }
        var shrunk = self
        if var device = frame.device {
            let candidates = devices.arrangements(for: device.model)
                .filter { $0.primaryModel == nil && $0.slots.count <= max(count, 1) }
                .sorted { $0.slots.count > $1.slots.count }
            device.arrangement = candidates.first?.id ?? DeviceArrangement.singleID
            shrunk.frame.device = device
            return shrunk
        }
        shrunk.collage = collages.layout(shrinkingTo: count, from: collage)?.id
        return shrunk
    }

    /// The same style with room for `count` screenshots, growing the device arrangement or screenshot layout
    /// (see `CollageCatalog.layout(toFit:from:)`); nil when no arrangement holds that many. A fixed device
    /// combination (laptop + phone…) never changes the device model.
    public func growing(
        toFit count: Int, devices: DeviceCatalog = .bundled, collages: CollageCatalog = .bundled
    ) -> Project? {
        if contentSlots(devices: devices, collages: collages).count >= count { return self }
        var grown = self
        if var device = frame.device {
            let candidates = devices.arrangements(for: device.model)
                .filter { $0.primaryModel == nil && $0.slots.count >= count }
                .sorted { $0.slots.count < $1.slots.count }
            guard let arrangement = candidates.first else { return nil }
            device.arrangement = arrangement.id
            grown.frame.device = device
            return grown
        }
        guard let layout = collages.layout(toFit: count, from: collage) else { return nil }
        grown.collage = layout.id
        return grown
    }
}
