/// One screenshot of a screenshot layout (S15), relative to the primary frame box: the centre in primary-box
/// widths / heights, the height as a multiple of the primary box height (the aspect is always the primary box's)
/// and a 2D rotation in degrees (positive = clockwise).
public struct CollageSlot: Hashable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let height: Double
    public let rotation: Double
    public let isPrimary: Bool

    public init(centerX: Double, centerY: Double, height: Double = 1, rotation: Double = 0, isPrimary: Bool = false) {
        self.centerX = centerX
        self.centerY = centerY
        self.height = height
        self.rotation = rotation
        self.isPrimary = isPrimary
    }

    /// The slot that shows the main image: laid out exactly like a document without a layout.
    public static let primary = CollageSlot(centerX: 0.5, centerY: 0.5, isPrimary: true)
}

/// A Sunshot screenshot layout (S15): 2–4 copies of the frame silhouette, drawn back to front.
public struct CollageArrangement: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Back to front.
    public let slots: [CollageSlot]

    public init(id: String, name: String, slots: [CollageSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    /// Index of the slot showing the main image (validated to exist in the bundled catalog).
    public var primaryIndex: Int { slots.firstIndex(where: \.isPrimary) ?? 0 }
}

public enum CollageCatalogError: Error, Equatable {
    case invalid(String)
}

/// Sunshot's screenshot layouts. Defined in code (they are few and purely geometric) and validated by
/// `validate()`, which the catalog tests run.
public struct CollageCatalog: Hashable, Sendable {
    public static let slotRange = 2...4
    public static let heightRange = 0.3...1.2
    public static let maxRotation = 30.0

    public let arrangements: [CollageArrangement]

    public init(arrangements: [CollageArrangement]) {
        self.arrangements = arrangements
    }

    public func arrangement(_ id: String?) -> CollageArrangement? {
        guard let id else { return nil }
        return arrangements.first { $0.id == id }
    }

    /// Which layout a full layout grows into when one more screenshot is added (paste or capture): the same
    /// look with one more slot. One screenshot grows into `startID`.
    public static let growth = [
        "side-by-side": "row", "overlap": "cascade", "cascade": "grid", "fan": "grid", "row": "grid",
    ]
    public static let startID = "side-by-side"

    /// Which layout a layout shrinks into when a screenshot is removed (the reverse of `growth`).
    public static let shrink = ["grid": "row", "row": "side-by-side", "cascade": "overlap", "fan": "side-by-side"]

    /// `current` if it has no more than `count` slots, else the first layout along `shrink` that doesn't; nil for
    /// one screenshot (or when the chain runs out).
    public func layout(shrinkingTo count: Int, from current: String?) -> CollageArrangement? {
        guard count > 1 else { return nil }
        var candidate = arrangement(current)
        var steps = 0
        while let layout = candidate, layout.slots.count > count, steps < arrangements.count {
            candidate = arrangement(Self.shrink[layout.id])
            steps += 1
        }
        return candidate
    }

    /// `current` if it holds `count` screenshots, else the first layout along `growth` that does; nil when none
    /// does (more screenshots than any layout has).
    public func layout(toFit count: Int, from current: String?) -> CollageArrangement? {
        var candidate = arrangement(current) ?? (count > 1 ? arrangement(Self.startID) : nil)
        var steps = 0
        while let layout = candidate, layout.slots.count < count, steps < arrangements.count {
            candidate = arrangement(Self.growth[layout.id])
            steps += 1
        }
        guard let layout = candidate, layout.slots.count >= count else { return nil }
        return layout
    }

    /// Throws on the first rule a layout breaks (see S15-AC1).
    public func validate() throws {
        var ids = Set<String>()
        var names = Set<String>()
        for arrangement in arrangements {
            let label = arrangement.id
            guard !arrangement.id.isEmpty, ids.insert(arrangement.id).inserted else {
                throw CollageCatalogError.invalid("duplicate or empty id \(label)")
            }
            guard !arrangement.name.isEmpty, names.insert(arrangement.name).inserted else {
                throw CollageCatalogError.invalid("duplicate or empty name in \(label)")
            }
            guard Self.slotRange.contains(arrangement.slots.count) else {
                throw CollageCatalogError.invalid("\(label) has \(arrangement.slots.count) slots")
            }
            let primaries = arrangement.slots.filter(\.isPrimary)
            guard primaries == [.primary] else {
                throw CollageCatalogError.invalid("\(label) needs exactly one primary slot at the centre")
            }
            for slot in arrangement.slots {
                guard Self.heightRange.contains(slot.height), abs(slot.rotation) <= Self.maxRotation,
                    slot.centerX.isFinite, slot.centerY.isFinite
                else { throw CollageCatalogError.invalid("\(label) has a slot out of range") }
            }
        }
    }

    public static let bundled = CollageCatalog(arrangements: [
        CollageArrangement(
            id: "side-by-side", name: "Side by Side",
            slots: [.primary, CollageSlot(centerX: 1.62, centerY: 0.5)]),
        CollageArrangement(
            id: "overlap", name: "Overlap",
            slots: [CollageSlot(centerX: 1.18, centerY: 0.24, height: 0.86), .primary]),
        CollageArrangement(
            id: "cascade", name: "Cascade",
            slots: [
                CollageSlot(centerX: 0.86, centerY: 0.14, height: 0.9),
                CollageSlot(centerX: 0.68, centerY: 0.32, height: 0.95), .primary,
            ]),
        CollageArrangement(
            id: "fan", name: "Fan",
            slots: [
                CollageSlot(centerX: 0.08, centerY: 0.56, height: 0.88, rotation: -9),
                CollageSlot(centerX: 0.92, centerY: 0.56, height: 0.88, rotation: 9), .primary,
            ]),
        CollageArrangement(
            id: "row", name: "Row of Three",
            // Left to right in paste order, so growing from Side by Side keeps every screenshot in place.
            slots: [.primary, CollageSlot(centerX: 1.62, centerY: 0.5), CollageSlot(centerX: 2.74, centerY: 0.5)]),
        CollageArrangement(
            id: "grid", name: "Grid",
            slots: [
                .primary, CollageSlot(centerX: 1.6, centerY: 0.5), CollageSlot(centerX: 0.5, centerY: 1.6),
                CollageSlot(centerX: 1.6, centerY: 1.6),
            ]),
    ])
}
