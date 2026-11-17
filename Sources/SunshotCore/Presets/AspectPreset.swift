public import Foundation

public struct AspectPreset: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Width / height.
    public let ratio: Double
    /// Display label such as `16:9`.
    public let label: String
    /// When set, exports must use exactly this size (store listings).
    public let exactSize: PixelSize?
}

public struct AspectPresetGroup: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let presets: [AspectPreset]
}

public enum AspectPresetCatalogError: Error, Equatable {
    case missingResource
    case invalid(String)
}

/// Aspect presets shipped as bundled JSON so they can be updated without code changes.
public enum AspectPresetCatalog {
    public static func load() throws -> [AspectPresetGroup] {
        guard let url = Bundle.module.url(forResource: "aspect-presets", withExtension: "json") else {
            throw AspectPresetCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes and validates catalogue JSON: unique ids, positive finite ratios, non-empty names.
    public static func decode(_ data: Data) throws -> [AspectPresetGroup] {
        let groups = try JSONDecoder().decode([AspectPresetGroup].self, from: data)
        var seen = Set<String>()
        for preset in groups.flatMap(\.presets) {
            guard seen.insert(preset.id).inserted else {
                throw AspectPresetCatalogError.invalid("duplicate id \(preset.id)")
            }
            guard preset.ratio.isFinite, preset.ratio > 0 else {
                throw AspectPresetCatalogError.invalid("bad ratio for \(preset.id)")
            }
            guard !preset.name.isEmpty else {
                throw AspectPresetCatalogError.invalid("empty name for \(preset.id)")
            }
        }
        return groups
    }
}
