public import Foundation

public struct Swatch: Hashable, Sendable, Identifiable {
    public let name: String
    public let color: RGBAColor
    /// The hex value is the identity: no two swatches share one.
    public var id: String { color.hexString }
}

public struct SwatchGroup: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let swatches: [Swatch]
}

public struct GradientPreset: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let spec: GradientSpec
}

public enum BackdropCatalogError: Error, Equatable {
    case missingResource(String)
    case invalid(String)
}

/// Sunshot's own swatches, gradient presets and wallpaper recipes, shipped as bundled JSON.
public enum BackdropCatalog {
    public static func swatchGroups() throws -> [SwatchGroup] { try decodeSwatches(resource("swatches")) }
    public static func gradientPresets() throws -> [GradientPreset] {
        try decodeGradients(resource("gradient-presets"))
    }
    public static func wallpapers() throws -> [Wallpaper] { try decodeWallpapers(resource("wallpapers")) }

    /// Bundled resource names, so tests can check the payload size and provenance.
    public static let resourceNames = ["swatches", "gradient-presets", "wallpapers"]

    public static func resourceURL(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "json")
    }

    private static func resource(_ name: String) throws -> Data {
        guard let url = resourceURL(name) else { throw BackdropCatalogError.missingResource(name) }
        return try Data(contentsOf: url)
    }

    // MARK: Decoding (hex strings in JSON → model values, validated)

    private struct SwatchGroupFile: Decodable {
        let id: String
        let name: String
        let swatches: [NamedHex]
    }

    private struct NamedHex: Decodable {
        let name: String
        let hex: String
    }

    private struct StopFile: Decodable {
        let position: Double
        let hex: String
    }

    private struct GradientFile: Decodable {
        let id: String
        let name: String
        let kind: GradientKind
        let angle: Double
        let stops: [StopFile]
    }

    private struct WallpaperFile: Decodable {
        let id: String
        let name: String
        let seed: UInt64
        let base: GradientFile
        let palette: [String]
        let fields: Int
    }

    public static func decodeSwatches(_ data: Data) throws -> [SwatchGroup] {
        let files = try JSONDecoder().decode([SwatchGroupFile].self, from: data)
        let groups = try files.map { group in
            SwatchGroup(
                id: group.id, name: group.name,
                swatches: try group.swatches.map { Swatch(name: $0.name, color: try color($0.hex)) })
        }
        try requireUnique(groups.flatMap(\.swatches).map(\.id), what: "swatch colour")
        try requireNamed(groups.flatMap(\.swatches).map(\.name))
        return groups
    }

    public static func decodeGradients(_ data: Data) throws -> [GradientPreset] {
        let presets = try JSONDecoder().decode([GradientFile].self, from: data).map(gradient)
        try requireUnique(presets.map(\.id), what: "gradient id")
        try requireUnique(presets.map(\.name), what: "gradient name")
        try requireUnique(presets.map { "\($0.spec)" }, what: "gradient value")
        try requireNamed(presets.map(\.name))
        return presets
    }

    public static func decodeWallpapers(_ data: Data) throws -> [Wallpaper] {
        let wallpapers = try JSONDecoder().decode([WallpaperFile].self, from: data).map { file in
            guard !file.palette.isEmpty, file.fields > 0 else {
                throw BackdropCatalogError.invalid("wallpaper \(file.id) needs a palette and colour fields")
            }
            return Wallpaper(
                id: file.id, name: file.name, seed: file.seed, base: try gradient(file.base).spec,
                palette: try file.palette.map(color), fieldCount: file.fields)
        }
        try requireUnique(wallpapers.map(\.id), what: "wallpaper id")
        try requireUnique(wallpapers.map(\.seed).map(String.init), what: "wallpaper seed")
        try requireNamed(wallpapers.map(\.name))
        return wallpapers
    }

    private static func gradient(_ file: GradientFile) throws -> GradientPreset {
        guard GradientSpec.stopCount.contains(file.stops.count) else {
            throw BackdropCatalogError.invalid("gradient \(file.id) needs 2…12 stops")
        }
        let stops = try file.stops.map { GradientStop(position: $0.position, color: try color($0.hex)) }
        return GradientPreset(
            id: file.id, name: file.name, spec: GradientSpec(kind: file.kind, angle: file.angle, stops: stops))
    }

    private static func color(_ hex: String) throws -> RGBAColor {
        guard let color = RGBAColor(hex: hex) else { throw BackdropCatalogError.invalid("bad colour \(hex)") }
        return color
    }

    private static func requireUnique(_ values: [String], what: String) throws {
        var seen = Set<String>()
        for value in values where !seen.insert(value).inserted {
            throw BackdropCatalogError.invalid("duplicate \(what) \(value)")
        }
    }

    private static func requireNamed(_ names: [String]) throws {
        if names.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw BackdropCatalogError.invalid("empty name")
        }
    }
}
