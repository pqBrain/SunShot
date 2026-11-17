public import Foundation

public enum DeviceCatalogError: Error, Equatable {
    case missingResource
    case invalid(String)
}

/// Sunshot's device mockups, finishes and multi-device arrangements, shipped as bundled JSON (`devices.json`).
/// The file is validated when it loads; a bad file refuses to load rather than drawing a broken device.
public struct DeviceCatalog: Hashable, Sendable {
    public static let resourceName = "devices"
    public static let defaultFinishID = "graphite"
    /// Allowed difference between a model's screen aspect and its recommended media aspect.
    public static let aspectTolerance = 0.01

    public let models: [DeviceModel]
    public let finishes: [DeviceFinish]
    public let arrangements: [DeviceArrangement]

    public init(models: [DeviceModel], finishes: [DeviceFinish], arrangements: [DeviceArrangement]) {
        self.models = models
        self.finishes = finishes
        self.arrangements = arrangements
    }

    public static let empty = DeviceCatalog(models: [], finishes: [], arrangements: [])

    /// The bundled catalog, loaded once. Empty if the file can't be read (no device is drawn then); the
    /// catalog tests and the app smoke test fail in that case.
    public static let bundled: DeviceCatalog = (try? load()) ?? .empty

    public static func load() throws -> DeviceCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw DeviceCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    public func model(_ id: String) -> DeviceModel? { models.first { $0.id == id } }
    public func finish(_ id: String) -> DeviceFinish? { finishes.first { $0.id == id } }
    public func arrangement(_ id: String) -> DeviceArrangement? { arrangements.first { $0.id == id } }

    /// The first model of `category`.
    public func model(in category: DeviceCategory) -> DeviceModel? { models.first { $0.category == category } }

    /// Arrangements that can show `model`: those using the selected model, and those whose primary is it.
    public func arrangements(for model: String) -> [DeviceArrangement] {
        arrangements.filter { $0.primaryModel == nil || $0.primaryModel == model }
    }

    // MARK: Decoding

    public static func decode(_ data: Data) throws -> DeviceCatalog {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw DeviceCatalogError.invalid("malformed JSON: \(error)")
        }
        let finishes = try file.finishes.map { try $0.finish }
        let models = try file.models.map { try $0.model }
        try requireUnique(finishes.map(\.id), "finish id")
        try requireUnique(finishes.map { $0.name.lowercased() }, "finish name")
        try requireUnique(models.map(\.id), "model id")
        try requireUnique(models.map { $0.name.lowercased() }, "model name")
        guard finishes.contains(where: { $0.id == defaultFinishID }) else { throw invalid("no default finish") }
        guard !models.isEmpty else { throw invalid("no models") }
        let ids = Set(models.map(\.id))
        let arrangements = try file.arrangements.map { try $0.arrangement(models: ids) }
        try requireUnique(arrangements.map(\.id), "arrangement id")
        try requireUnique(arrangements.map { $0.name.lowercased() }, "arrangement name")
        guard let first = arrangements.first, first.id == DeviceArrangement.singleID, first.slots.count == 1 else {
            throw invalid("the first arrangement must be \"single\" with one slot")
        }
        return DeviceCatalog(models: models, finishes: finishes, arrangements: arrangements)
    }

    static func invalid(_ reason: String) -> DeviceCatalogError { .invalid(reason) }

    private static func requireUnique(_ values: [String], _ what: String) throws {
        var seen = Set<String>()
        for value in values {
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { throw invalid("empty \(what)") }
            guard seen.insert(value).inserted else { throw invalid("duplicate \(what) \(value)") }
        }
    }

    private struct RawFile: Decodable {
        let finishes: [RawFinish]
        let models: [RawModel]
        let arrangements: [RawArrangement]
    }

    private struct RawFinish: Decodable {
        let id: String
        let name: String
        let shell: String
        let highlight: String
        let edge: String
        let bezel: String
        let detail: String

        var finish: DeviceFinish {
            get throws {
                func color(_ hex: String) throws -> RGBAColor {
                    guard let color = RGBAColor(hex: hex), color.alpha == 1 else {
                        throw DeviceCatalog.invalid("bad colour \(hex) in finish \(id)")
                    }
                    return color
                }
                return DeviceFinish(
                    id: id, name: name, shell: try color(shell), highlight: try color(highlight),
                    edge: try color(edge), bezel: try color(bezel), detail: try color(detail))
            }
        }
    }

    private struct RawSize: Decodable {
        let width: Int
        let height: Int

        func size(_ id: String) throws -> PixelSize {
            guard width > 0, height > 0 else { throw DeviceCatalog.invalid("bad size in \(id)") }
            return PixelSize(width: width, height: height)
        }
    }

    private struct RawPart: Decodable {
        let role: DevicePartRole
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let radius: Double?

        func part(_ id: String) throws -> DevicePart {
            let radius = radius ?? 0
            let values = [x, y, width, height, radius]
            guard values.allSatisfy(\.isFinite), width > 0, height > 0, radius >= 0,
                radius <= min(width, height) / 2
            else { throw DeviceCatalog.invalid("bad \(role.rawValue) part in \(id)") }
            return DevicePart(role: role, rect: LayoutRect(x: x, y: y, width: width, height: height), radius: radius)
        }
    }

    private struct RawModel: Decodable {
        let id: String
        let name: String
        let category: DeviceCategory
        let rotatable: Bool
        let recommended: RawSize
        let captureSizes: [RawSize]
        let parts: [RawPart]

        var model: DeviceModel {
            get throws {
                let parts = try parts.map { try $0.part(id) }
                guard parts.filter({ $0.role == .screen }).count == 1 else {
                    throw DeviceCatalog.invalid("\(id) needs exactly one screen")
                }
                let model = DeviceModel(
                    id: id, name: name, category: category, rotatable: rotatable,
                    recommendedSize: try recommended.size(id), captureSizes: try captureSizes.map { try $0.size(id) },
                    parts: parts)
                let aspect = model.recommendedSize.aspectRatio
                guard abs(model.screenAspect / aspect - 1) <= DeviceCatalog.aspectTolerance else {
                    throw DeviceCatalog.invalid("\(id): screen aspect doesn't match the recommended size")
                }
                return model
            }
        }
    }

    private struct RawSlot: Decodable {
        let model: String?
        let x: Double?
        let y: Double?
        let height: Double?
        let primary: Bool?
    }

    private struct RawArrangement: Decodable {
        let id: String
        let name: String
        let slots: [RawSlot]

        func arrangement(models: Set<String>) throws -> DeviceArrangement {
            let slots = try slots.map { raw in
                let slot = DeviceSlot(
                    model: raw.model, centerX: raw.x ?? 0, centerY: raw.y ?? 0, height: raw.height ?? 1,
                    isPrimary: raw.primary ?? false)
                guard [slot.centerX, slot.centerY, slot.height].allSatisfy(\.isFinite), slot.height > 0,
                    slot.height <= 2, abs(slot.centerX) <= 2, abs(slot.centerY) <= 2
                else { throw DeviceCatalog.invalid("bad slot in \(id)") }
                if let model = slot.model, !models.contains(model) {
                    throw DeviceCatalog.invalid("unknown model \(model) in \(id)")
                }
                return slot
            }
            let primaries = slots.filter(\.isPrimary)
            guard primaries.count == 1, let primary = primaries.first else {
                throw DeviceCatalog.invalid("\(id) needs exactly one primary slot")
            }
            guard primary.centerX == 0, primary.centerY == 0, primary.height == 1 else {
                throw DeviceCatalog.invalid("\(id): the primary slot sits at the origin at full size")
            }
            return DeviceArrangement(id: id, name: name, slots: slots)
        }
    }
}
