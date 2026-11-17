public import Foundation

/// A named content transform shown in the layout list.
public struct LayoutPreset: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let transform: ContentTransform

    public init(id: String, name: String, transform: ContentTransform) {
        self.id = id
        self.name = name
        self.transform = transform
    }
}

public enum LayoutPresetCatalogError: Error, Equatable {
    case missingResource
    case invalid(String)
}

/// Sunshot's layout presets, shipped as bundled JSON (`layout-presets.json`). The first preset is the identity
/// ("Centered"). Values in the file must already be in range: the catalog refuses to load rather than clamp.
public struct LayoutPresetCatalog: Hashable, Sendable {
    public let presets: [LayoutPreset]

    public static let resourceName = "layout-presets"

    public static func load() throws -> LayoutPresetCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw LayoutPresetCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    public func preset(id: String?) -> LayoutPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    /// Decodes and validates: ≥ 1 preset, unique non-empty ids and names, every value finite and in range,
    /// zoom a whole percent, and the first preset is the identity.
    public static func decode(_ data: Data) throws -> LayoutPresetCatalog {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw LayoutPresetCatalogError.invalid("malformed JSON: \(error)")
        }
        var ids = Set<String>()
        var names = Set<String>()
        var presets: [LayoutPreset] = []
        for raw in file.presets {
            let name = raw.name.trimmingCharacters(in: .whitespaces)
            guard !raw.id.isEmpty, ids.insert(raw.id).inserted else { throw invalid("duplicate or empty id \(raw.id)") }
            guard !name.isEmpty, names.insert(name.lowercased()).inserted else {
                throw invalid("duplicate or empty name \(raw.id)")
            }
            presets.append(LayoutPreset(id: raw.id, name: name, transform: try raw.transform.validated(raw.id)))
        }
        guard let first = presets.first else { throw invalid("no presets") }
        guard first.transform.isIdentity else { throw invalid("the first preset must be the identity") }
        return LayoutPresetCatalog(presets: presets)
    }

    static func invalid(_ reason: String) -> LayoutPresetCatalogError { .invalid(reason) }

    private struct RawFile: Decodable {
        let presets: [RawPreset]
    }

    private struct RawPreset: Decodable {
        let id: String
        let name: String
        let transform: RawTransform
    }

    private struct RawTransform: Decodable {
        var x: Double?
        var y: Double?
        var zoom: Double?
        var rotation: Double?
        var tiltX: Double?
        var tiltY: Double?

        func validated(_ id: String) throws -> ContentTransform {
            let checks: [(Double?, ClosedRange<Double>)] = [
                (x, ContentTransform.positionRange), (y, ContentTransform.positionRange),
                (zoom, ContentTransform.zoomRange), (rotation, ContentTransform.rotationRange),
                (tiltX, ContentTransform.tiltRange), (tiltY, ContentTransform.tiltRange),
            ]
            for (value, range) in checks {
                if let value, !(value.isFinite && range.contains(value)) {
                    throw LayoutPresetCatalog.invalid("value out of range in \(id)")
                }
            }
            if let zoom, zoom != zoom.rounded() { throw LayoutPresetCatalog.invalid("zoom must be whole in \(id)") }
            return ContentTransform(
                x: x ?? 0, y: y ?? 0, zoom: zoom ?? 100, rotation: rotation ?? 0, tiltX: tiltX ?? 0, tiltY: tiltY ?? 0)
        }
    }
}
