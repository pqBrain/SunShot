public import Foundation
import ImageIO
public import SunshotCore
import UniformTypeIdentifiers

/// A document read from a `.sunshot` package.
public struct LoadedDocument: Sendable {
    public var document: EditorDocument
    /// Written by a newer Sunshot: shown, but never saved over.
    public var isReadOnly: Bool
    /// Media that was missing or unreadable and replaced by a placeholder (only when placeholders were allowed).
    public var placeholders: [String]
}

/// Reads and writes `.sunshot` packages: `document.json` (see `DocumentManifest`) plus `media/` with each image's
/// original bytes. Writes are atomic: the package is built in a temporary folder and swapped in at the end, so an
/// interrupted save leaves the previous version intact.
public enum DocumentPackage {
    public static let fileExtension = "sunshot"
    public static let typeIdentifier = "app.sunshot.document"

    // MARK: Write

    /// The manifest and media files for `document` (paths relative to the package).
    public static func contents(
        of document: EditorDocument
    ) throws -> (manifest: DocumentManifest, files: [String: Data]) {
        var files: [String: Data] = [:]
        var entries: [MediaEntry] = []
        var contentEntry: ContentEntry?
        if let content = document.content {
            let data = try content.data ?? ImageCodec.pngData(content.image)
            let id = content.id.uuidString
            let path = DocumentManifestCodec.mediaPath(id: id, fileExtension: fileExtension(for: data))
            files[path] = data
            entries.append(MediaEntry(id: id, path: path))
            contentEntry = ContentEntry(mediaID: id, pixelSize: content.pixelSize)
        }
        for (id, asset) in document.media.sorted(by: { $0.key < $1.key }) {
            let data = asset.data.isEmpty ? try ImageCodec.pngData(asset.image) : asset.data
            var path = DocumentManifestCodec.mediaPath(id: id, fileExtension: fileExtension(for: data))
            if files[path] != nil {
                path = DocumentManifestCodec.mediaPath(id: "\(id)-\(entries.count)", fileExtension: "png")
            }
            files[path] = data
            entries.append(MediaEntry(id: id, path: path, fileName: asset.reference.fileName))
        }
        let manifest = DocumentManifest(
            project: document.project, content: contentEntry, media: entries, theme: document.theme)
        return (manifest, files)
    }

    /// Writes `document` to `url` atomically. `beforeCommit` runs after everything is written to the temporary
    /// copy and before it replaces `url` (tests use it to simulate an interrupted save).
    public static func write(
        _ document: EditorDocument, to url: URL, beforeCommit: () throws -> Void = {}
    ) throws {
        let (manifest, files) = try contents(of: document)
        let fileManager = FileManager.default
        let scratch =
            (try? fileManager.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true))
            ?? fileManager.temporaryDirectory.appendingPathComponent("sunshot-save-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: scratch) }
        let staged = scratch.appendingPathComponent(url.lastPathComponent)
        try fileManager.createDirectory(
            at: staged.appendingPathComponent(DocumentManifest.mediaFolder), withIntermediateDirectories: true)
        for (path, data) in files {
            try data.write(to: staged.appendingPathComponent(path))
        }
        try DocumentManifestCodec.encode(manifest).write(to: staged.appendingPathComponent(DocumentManifest.fileName))
        try beforeCommit()
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: staged)
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: staged, to: url)
        }
    }

    // MARK: Read

    /// Reads a package. Never reads outside it. Missing, empty or damaged media throws `.missingMedia` unless
    /// `allowPlaceholders` is set, in which case content becomes a grey placeholder of the recorded size and a
    /// missing backdrop image falls back to the default colour.
    public static func read(from url: URL, allowPlaceholders: Bool = false) throws -> LoadedDocument {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw DocumentFormatError.missingManifest
        }
        guard isDirectory.boolValue else { throw DocumentFormatError.notAPackage }
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = root.appendingPathComponent(DocumentManifest.fileName)
        guard let manifestData = try? Data(contentsOf: manifestURL) else { throw DocumentFormatError.missingManifest }
        let decoded = try DocumentManifestCodec.decode(manifestData)
        let manifest = decoded.manifest

        var loaded: [String: (data: Data, image: CGImage)] = [:]
        var missing: [String] = []
        for entry in manifest.media {
            let file = try contained(entry.path, in: root)
            if let data = try? Data(contentsOf: file), !data.isEmpty, let image = try? ImageLoader.load(data) {
                loaded[entry.id] = (data, image)
            } else {
                missing.append(entry.fileName ?? entry.path)
            }
        }
        if !missing.isEmpty && !allowPlaceholders { throw DocumentFormatError.missingMedia(missing) }

        var document = EditorDocument(project: manifest.project, theme: manifest.theme)
        if let content = manifest.content {
            let id = UUID(uuidString: content.mediaID) ?? UUID()
            if let file = loaded[content.mediaID] {
                document.content = ContentImage(file.image, id: id, data: file.data)
            } else {
                document.content = ContentImage(try placeholder(size: content.pixelSize), id: id)
            }
        }
        for entry in manifest.media where entry.id != manifest.content?.mediaID {
            guard let file = loaded[entry.id] else { continue }
            let reference = MediaReference(
                id: entry.id, fileName: entry.fileName,
                pixelSize: PixelSize(width: file.image.width, height: file.image.height))
            document.media[entry.id] = MediaAsset(reference: reference, data: file.data, image: file.image)
        }
        return LoadedDocument(document: document, isReadOnly: decoded.isReadOnly, placeholders: missing)
    }

    /// `path` resolved inside `root`; anything that would leave the package (`..`, symlinks) is refused.
    static func contained(_ path: String, in root: URL) throws -> URL {
        try DocumentManifestCodec.validate(path: path)
        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let folder = root.appendingPathComponent(DocumentManifest.mediaFolder).path + "/"
        guard file.path.hasPrefix(folder) else { throw DocumentFormatError.unsafePath(path) }
        return file
    }

    /// Mid-grey image shown in place of missing content.
    static func placeholder(size: PixelSize) throws -> CGImage {
        let width = min(size.width, SunshotDefaults.maxCanvasSide)
        let height = min(size.height, SunshotDefaults.maxCanvasSide)
        guard let context = Renderer.makeContext(width: width, height: height) else {
            throw RenderError.contextCreationFailed
        }
        context.setFillColor(CGColor(srgbRed: 0.6, green: 0.6, blue: 0.63, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }

    /// The file extension matching the image bytes (`png`, `jpeg`, `heic`…), `bin` if unknown.
    static func fileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source) as String?,
            let ext = UTType(identifier)?.preferredFilenameExtension
        else { return "bin" }
        return ext
    }
}
