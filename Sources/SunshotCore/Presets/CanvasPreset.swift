public import Foundation

/// The three preset groups, in display order.
public enum CanvasPresetGroupID: String, Codable, CaseIterable, Hashable, Sendable {
    case general, social, store
}

public struct CanvasPresetGroup: Codable, Hashable, Sendable, Identifiable {
    public let id: CanvasPresetGroupID
    public let name: String
}

/// A canvas size preset. Ratio presets grow the canvas around the content; presets with `pixelW`/`pixelH`
/// (store listings) export at exactly that size.
public struct CanvasPreset: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let group: CanvasPresetGroupID
    public let name: String
    public let ratioW: Double
    public let ratioH: Double
    public let pixelW: Int?
    public let pixelH: Int?

    public init(
        id: String, group: CanvasPresetGroupID, name: String, ratioW: Double, ratioH: Double, pixelW: Int? = nil,
        pixelH: Int? = nil
    ) {
        self.id = id
        self.group = group
        self.name = name
        self.ratioW = ratioW
        self.ratioH = ratioH
        self.pixelW = pixelW
        self.pixelH = pixelH
    }

    /// Width / height.
    public var ratio: Double { ratioW / ratioH }

    /// The exact export size, for store presets.
    public var exactSize: PixelSize? {
        guard let pixelW, let pixelH else { return nil }
        return PixelSize(width: pixelW, height: pixelH)
    }

    /// `16:9`, `1.91:1`, `9:19.5`.
    public var ratioLabel: String { "\(Self.format(ratioW)):\(Self.format(ratioH))" }

    /// What the tile shows under the shape: the exact size for store presets, otherwise the ratio.
    public var sizeLabel: String {
        guard let exactSize else { return ratioLabel }
        return "\(exactSize.width)×\(exactSize.height)"
    }

    /// `16`, `1.91`, `19.5`: whole numbers without decimals, others with up to three.
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e9 { return String(Int(value)) }
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

public enum CanvasPresetCatalogError: Error, Equatable {
    case missingResource
    case invalid(String)
}

/// Where a store size came from, and when it was last checked.
public struct CanvasPresetSource: Codable, Hashable, Sendable {
    public let about: String
    public let url: String
    public let checked: String
}

/// Canvas size presets shipped as bundled JSON (`canvas-presets.json`) so they can be updated without code.
public struct CanvasPresetCatalog: Codable, Hashable, Sendable {
    public let groups: [CanvasPresetGroup]
    public let sources: [CanvasPresetSource]
    public let presets: [CanvasPreset]

    /// Exact store sizes may differ from the nominal ratio by at most this fraction.
    public static let ratioTolerance = 0.005

    public static func load() throws -> CanvasPresetCatalog {
        guard let url = Bundle.module.url(forResource: "canvas-presets", withExtension: "json") else {
            throw CanvasPresetCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes and validates: unique ids, known groups, positive ratios, non-empty names, and every store
    /// preset has an exact size (1…max side) matching its ratio.
    public static func decode(_ data: Data) throws -> CanvasPresetCatalog {
        let catalog: CanvasPresetCatalog
        do {
            catalog = try JSONDecoder().decode(CanvasPresetCatalog.self, from: data)
        } catch {
            throw CanvasPresetCatalogError.invalid("malformed JSON: \(error)")
        }
        try catalog.validate()
        return catalog
    }

    private func validate() throws {
        let declared = Set(groups.map(\.id))
        var seen = Set<String>()
        for preset in presets {
            let id = preset.id
            guard !id.isEmpty, seen.insert(id).inserted else { throw invalid("duplicate or empty id \(id)") }
            guard declared.contains(preset.group) else { throw invalid("undeclared group for \(id)") }
            guard !preset.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw invalid("empty name \(id)") }
            guard preset.ratioW.isFinite, preset.ratioH.isFinite, preset.ratioW > 0, preset.ratioH > 0 else {
                throw invalid("bad ratio for \(id)")
            }
            if preset.group == .store, preset.exactSize == nil { throw invalid("store preset \(id) needs pixelW/H") }
            guard (preset.pixelW == nil) == (preset.pixelH == nil) else { throw invalid("half a pixel size \(id)") }
            if let pixelW = preset.pixelW, let pixelH = preset.pixelH {
                let range = 1...SunshotDefaults.maxCanvasSide
                guard range.contains(pixelW), range.contains(pixelH) else { throw invalid("size out of range \(id)") }
                let actual = Double(pixelW) / Double(pixelH)
                guard abs(actual / preset.ratio - 1) <= Self.ratioTolerance else {
                    throw invalid("pixel size of \(id) doesn't match its ratio")
                }
            }
        }
    }

    private func invalid(_ reason: String) -> CanvasPresetCatalogError { .invalid(reason) }

    public func group(_ id: CanvasPresetGroupID) -> CanvasPresetGroup? { groups.first { $0.id == id } }

    public func preset(id: String) -> CanvasPreset? { presets.first { $0.id == id } }

    /// Case-insensitive, whitespace-trimmed match on name, group name, ratio or exact size; empty = everything.
    public func search(_ query: String) -> [CanvasPreset] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return presets }
        return presets.filter { preset in
            let haystack = [
                preset.name, group(preset.group)?.name ?? preset.group.rawValue, preset.ratioLabel, preset.sizeLabel,
                preset.sizeLabel.replacingOccurrences(of: "×", with: "x"),
            ]
            return haystack.contains { $0.lowercased().contains(needle) }
        }
    }

    /// Search results in group order, leaving out empty groups.
    public func sections(matching query: String) -> [(group: CanvasPresetGroup, presets: [CanvasPreset])] {
        let matches = search(query)
        return groups.compactMap { group in
            let inGroup = matches.filter { $0.group == group.id }
            return inGroup.isEmpty ? nil : (group, inGroup)
        }
    }
}
