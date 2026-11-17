import Foundation

/// The four families of Sunshot-drawn device mockups (S12).
public enum DeviceCategory: String, Codable, CaseIterable, Sendable {
    case phone, tablet, laptop, desktop
}

/// What a device part is painted with. Colours come from the chosen `DeviceFinish`.
public enum DevicePartRole: String, Codable, CaseIterable, Sendable {
    /// The body: a top-to-bottom gradient from the finish highlight to the shell colour, with an edge outline.
    case shell
    /// Buttons, hinges and feet: the finish edge colour.
    case edge
    /// The dark glass around the screen.
    case bezel
    /// Small accents (keyboard-deck lip, stand collar): the finish detail colour.
    case detail
    /// A camera lens: a dark disc with a thin ring.
    case lens
    /// Where the content goes (exactly one per device).
    case screen
}

/// One vector shape of a device: a rounded rectangle (continuous corners) in device units.
public struct DevicePart: Hashable, Sendable {
    public let role: DevicePartRole
    public let rect: LayoutRect
    public let radius: Double

    public init(role: DevicePartRole, rect: LayoutRect, radius: Double) {
        self.role = role
        self.rect = rect
        self.radius = radius
    }
}

/// A device drawn by Sunshot: its parts in back-to-front order, normalised so the bounding box starts at 0, 0.
public struct DeviceModel: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: DeviceCategory
    /// Phones and tablets can be turned to landscape; laptops and monitors cannot.
    public let rotatable: Bool
    /// The media size that fills the screen exactly (portrait for rotatable devices).
    public let recommendedSize: PixelSize
    /// Common capture sizes of this kind of device; an exact match makes the suggestion certain.
    public let captureSizes: [PixelSize]
    public let parts: [DevicePart]
    public let width: Double
    public let height: Double

    public init(
        id: String, name: String, category: DeviceCategory, rotatable: Bool, recommendedSize: PixelSize,
        captureSizes: [PixelSize], parts: [DevicePart]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.rotatable = rotatable
        self.recommendedSize = recommendedSize
        self.captureSizes = captureSizes
        let minX = parts.map(\.rect.x).min() ?? 0
        let minY = parts.map(\.rect.y).min() ?? 0
        let maxX = parts.map { $0.rect.x + $0.rect.width }.max() ?? 0
        let maxY = parts.map { $0.rect.y + $0.rect.height }.max() ?? 0
        self.parts = parts.map {
            DevicePart(
                role: $0.role,
                rect: LayoutRect(
                    x: $0.rect.x - minX, y: $0.rect.y - minY, width: $0.rect.width, height: $0.rect.height),
                radius: $0.radius)
        }
        width = maxX - minX
        height = maxY - minY
    }

    /// The screen part (validated to exist when the catalog loads).
    public var screen: DevicePart? { parts.first { $0.role == .screen } }

    /// Width ÷ height of the screen.
    public var screenAspect: Double {
        guard let screen, screen.rect.height > 0 else { return 1 }
        return screen.rect.width / screen.rect.height
    }

    /// The same device turned a quarter clockwise (landscape); the recommended size swaps sides.
    public func rotated() -> DeviceModel {
        let turned = parts.map { part in
            DevicePart(
                role: part.role,
                rect: LayoutRect(
                    x: height - part.rect.y - part.rect.height, y: part.rect.x, width: part.rect.height,
                    height: part.rect.width),
                radius: part.radius)
        }
        return DeviceModel(
            id: id, name: name, category: category, rotatable: rotatable,
            recommendedSize: PixelSize(width: recommendedSize.height, height: recommendedSize.width),
            captureSizes: captureSizes.map { PixelSize(width: $0.height, height: $0.width) }, parts: turned)
    }

    /// Portrait as drawn, or rotated when `landscape` (only rotatable devices turn).
    public func oriented(landscape: Bool) -> DeviceModel {
        landscape && rotatable ? rotated() : self
    }
}

/// A colour finish: every device can be drawn in every finish.
public struct DeviceFinish: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let shell: RGBAColor
    public let highlight: RGBAColor
    public let edge: RGBAColor
    public let bezel: RGBAColor
    public let detail: RGBAColor

    public init(
        id: String, name: String, shell: RGBAColor, highlight: RGBAColor, edge: RGBAColor, bezel: RGBAColor,
        detail: RGBAColor
    ) {
        self.id = id
        self.name = name
        self.shell = shell
        self.highlight = highlight
        self.edge = edge
        self.bezel = bezel
        self.detail = detail
    }
}

/// One device in a multi-device arrangement, placed relative to the primary device: centre offset in primary
/// widths (x) and heights (y), size as a fraction of the primary height. `model` nil = the selected model.
public struct DeviceSlot: Hashable, Sendable {
    public let model: String?
    public let centerX: Double
    public let centerY: Double
    public let height: Double
    public let isPrimary: Bool

    public init(model: String?, centerX: Double, centerY: Double, height: Double, isPrimary: Bool) {
        self.model = model
        self.centerX = centerX
        self.centerY = centerY
        self.height = height
        self.isPrimary = isPrimary
    }
}

/// The same content on one or more devices. Slots are drawn back to front; the primary slot's screen is the
/// content rect the canvas lays out.
public struct DeviceArrangement: Hashable, Sendable, Identifiable {
    public static let singleID = "single"

    public let id: String
    public let name: String
    public let slots: [DeviceSlot]

    public init(id: String, name: String, slots: [DeviceSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    /// The model the primary slot forces (e.g. a laptop for "laptop + phone"); nil when it uses the selection.
    public var primaryModel: String? { slots.first(where: \.isPrimary)?.model }
}

/// The device mockup chosen for a document: model, finish, orientation and arrangement (ids into the catalog).
/// Stored in `Frame.device`; nil there means no device. Unknown ids (from a newer version) draw no device.
public struct DeviceSelection: Codable, Hashable, Sendable {
    public var model: String
    public var finish: String
    public var landscape: Bool
    public var arrangement: String

    public init(
        model: String, finish: String = DeviceCatalog.defaultFinishID, landscape: Bool = false,
        arrangement: String = DeviceArrangement.singleID
    ) {
        self.model = model
        self.finish = finish
        self.landscape = landscape
        self.arrangement = arrangement
    }

    private enum CodingKeys: String, CodingKey { case model, finish, landscape, arrangement }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            model: try container.decode(String.self, forKey: .model),
            finish: try container.decodeIfPresent(String.self, forKey: .finish) ?? DeviceCatalog.defaultFinishID,
            landscape: try container.decodeIfPresent(Bool.self, forKey: .landscape) ?? false,
            arrangement: try container.decodeIfPresent(String.self, forKey: .arrangement)
                ?? DeviceArrangement.singleID)
    }
}
