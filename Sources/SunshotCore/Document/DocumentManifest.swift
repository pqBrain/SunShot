public import Foundation

/// `document.json` inside a `.sunshot` package: the whole `Project` and where each media file lives. Media bytes
/// are never stored in the JSON. (Documents saved before S17 may also hold a `theme` record; it is ignored.)
///
/// Decoding is tolerant: the stored JSON is laid over the JSON of a default document, so fields added by later
/// versions (or other slices) take their defaults when missing, and unknown keys are ignored.
public struct DocumentManifest: Codable, Hashable, Sendable {
    /// The schema this app writes. Raise it only together with a migration, a fixture and a test.
    public static let currentSchemaVersion = 1
    public static let fileName = "document.json"
    public static let mediaFolder = "media"

    public var schemaVersion: Int
    public var project: Project
    /// The content image, or nil for an empty document.
    public var content: ContentEntry?
    /// Every media file in the package (content and user backdrop images), keyed by id.
    public var media: [MediaEntry]
    /// Code-snippet content (S11), stored inline; nil for image or empty documents.
    public var snippet: CodeSnippet?
    /// Non-destructive crop of the content image (S10), in its pixels; nil (or missing) = the whole image.
    public var crop: CropRect?
    /// Video content (S13): which media file is the movie. Nil for image, snippet or empty documents.
    public var video: VideoEntry?
    /// S15: slot images (which media file shows in which slot). Nil (omitted) when the document has none.
    public var slots: [SlotEntry]?

    public init(
        schemaVersion: Int = DocumentManifest.currentSchemaVersion, project: Project = Project(),
        content: ContentEntry? = nil, media: [MediaEntry] = [], snippet: CodeSnippet? = nil,
        crop: CropRect? = nil, video: VideoEntry? = nil, slots: [SlotEntry]? = nil
    ) {
        self.slots = slots
        self.snippet = snippet
        self.crop = crop
        self.video = video
        self.schemaVersion = schemaVersion
        self.project = project
        self.content = content
        self.media = media
    }
}

/// The content image: which media file holds its original bytes and its size (used for a placeholder when the
/// file is missing).
public struct ContentEntry: Codable, Hashable, Sendable {
    public var mediaID: String
    public var pixelSize: PixelSize

    public init(mediaID: String, pixelSize: PixelSize) {
        self.mediaID = mediaID
        self.pixelSize = pixelSize
    }
}

/// An S15 slot image: the screenshot number (1, 2…), its media file and its size (for a placeholder when the
/// file is missing).
public struct SlotEntry: Codable, Hashable, Sendable {
    public var number: Int
    public var mediaID: String
    public var pixelSize: PixelSize

    public init(number: Int, mediaID: String, pixelSize: PixelSize) {
        self.number = number
        self.mediaID = mediaID
        self.pixelSize = pixelSize
    }
}

/// One file in the package's `media/` folder.
public struct MediaEntry: Codable, Hashable, Sendable {
    public var id: String
    /// Package-relative path, always `media/<name>`.
    public var path: String
    /// The name of the file the user imported, if known.
    public var fileName: String?

    public init(id: String, path: String, fileName: String? = nil) {
        self.id = id
        self.path = path
        self.fileName = fileName
    }
}

public enum DocumentFormatError: Error, Equatable, Sendable {
    case missingManifest
    case invalidJSON(String)
    case missingMedia([String])
    case unsafePath(String)
    case notAPackage

    /// One-line, user-facing reason shown under "Can't open this document".
    public var reason: String {
        switch self {
        case .missingManifest: "The document is missing its contents file (document.json)."
        case .invalidJSON(let detail): "The document's contents file is damaged (\(detail))."
        case .missingMedia(let names):
            "Some images are missing or empty: \(names.joined(separator: ", "))."
        case .unsafePath(let path): "The document refers to a file outside itself (\(path))."
        case .notAPackage: "This isn't a Sunshot document."
        }
    }
}

/// The result of decoding `document.json`.
public struct DecodedManifest: Sendable {
    public var manifest: DocumentManifest
    /// True when the file was written by a newer Sunshot: it opens read-only so it is never overwritten with
    /// fewer fields than it had.
    public var isReadOnly: Bool
}

public enum DocumentManifestCodec {
    public static let newerVersionMessage = "This document was made with a newer version of Sunshot"

    /// Pretty, key-sorted JSON (stable diffs, readable when debugging).
    public static func encode(_ manifest: DocumentManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    public static func decode(_ data: Data) throws -> DecodedManifest {
        let json: JSONValue
        do {
            json = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw DocumentFormatError.invalidJSON("not valid JSON")
        }
        guard case .object = json else { throw DocumentFormatError.invalidJSON("not a JSON object") }
        guard case .int(let version) = json["schemaVersion"] ?? .null, version >= 1 else {
            throw DocumentFormatError.invalidJSON("no schema version")
        }
        let migrated = migrate(json, from: version)
        do {
            var manifest = try migrated.decodeTolerantly(DocumentManifest.self, defaults: DocumentManifest())
            manifest.schemaVersion = version
            for entry in manifest.media { try validate(path: entry.path) }
            if let content = manifest.content, !manifest.media.contains(where: { $0.id == content.mediaID }) {
                throw DocumentFormatError.missingMedia([content.mediaID])
            }
            for slot in manifest.slots ?? [] where !manifest.media.contains(where: { $0.id == slot.mediaID }) {
                throw DocumentFormatError.missingMedia([slot.mediaID])
            }
            return DecodedManifest(manifest: manifest, isReadOnly: version > DocumentManifest.currentSchemaVersion)
        } catch let error as DocumentFormatError {
            throw error
        } catch {
            throw DocumentFormatError.invalidJSON("unexpected values")
        }
    }

    /// Upgrades older schemas to the current one. Version 1 is the first; each future step gets a fixture
    /// (`fixtures/v<n>/document.json`) and a test.
    static func migrate(_ json: JSONValue, from version: Int) -> JSONValue { json }

    /// Media paths must be `media/<name>` with a plain name: no traversal, no hidden files, no sub-folders.
    public static func validate(path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == Substring(DocumentManifest.mediaFolder), let name = parts.last,
            !name.isEmpty, !name.hasPrefix("."), !name.contains("\\"), !name.contains(":"),
            name.unicodeScalars.allSatisfy({ $0.value >= 0x20 })
        else { throw DocumentFormatError.unsafePath(path) }
    }

    /// `media/<id>.<ext>` for a new media file (ids are sanitised so the path always validates).
    public static func mediaPath(id: String, fileExtension: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var name = String(id.filter { allowed.contains($0) }.prefix(80))
        if name.isEmpty { name = "media" }
        let ext = String(fileExtension.lowercased().filter { allowed.contains($0) }.prefix(8))
        return "\(DocumentManifest.mediaFolder)/\(name)\(ext.isEmpty ? "" : ".\(ext)")"
    }
}
