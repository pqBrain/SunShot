public import Foundation

/// S16: the user's default style and layout ("Save as Default Style"). It styles every quick capture copied to the
/// clipboard and is the starting point of new documents in the studio. It is a whole `Project` minus what belongs
/// to one image (annotations, animation, screenshot layout), so canvas, padding, backdrop, frame, shadow, tilt and
/// export options all carry over.
public struct QuickStyle: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var project: Project
    /// When it was saved (shown in Settings).
    public var savedAt: Date

    public init(project: Project, savedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.project = Self.styleOnly(project)
        self.savedAt = savedAt
    }

    /// `project` without its per-image parts.
    public static func styleOnly(_ project: Project) -> Project {
        var style = project
        style.annotationLayer = nil
        style.animation = nil
        style.collage = nil
        return style
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Throws for unreadable data or a style saved by a newer Sunshot.
    public static func decode(_ data: Data) throws -> QuickStyle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let style = try decoder.decode(QuickStyle.self, from: data)
        guard style.schemaVersion <= currentSchemaVersion else {
            throw DocumentFormatError.invalidJSON("default style from a newer version")
        }
        return style
    }
}
