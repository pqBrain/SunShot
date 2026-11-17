import CoreGraphics
import CryptoKit
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

/// A temporary folder removed after the test.
struct ScratchFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("sunshot-doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    func cleanUp() { try? FileManager.default.removeItem(at: url) }
}

enum DocumentFixtures {
    /// Content + user backdrop image + non-default border, shadow, canvas size and export options.
    static func styledSession(contentSize: Int = 300) throws -> EditorSession {
        var session = EditorSession()
        try session.importImage(
            data: Fixtures.encode(try Fixtures.noise(width: contentSize, height: contentSize / 2), as: .png))
        try session.importBackdropImage(
            data: Fixtures.encode(try Fixtures.solid(width: 64, height: 48, red: 0.9), as: .jpeg), fileName: "sky.jpg")
        session.setCornerStyle(.round)
        session.setCornerRadius(36)
        session.setShadowStyle(.hug)
        session.setShadowIntensity(.high)
        session.setLightPosition(UnitOffset(x: 0.4, y: -0.2))
        session.setCanvas(.ratio(16.0 / 9.0))
        session.setExportFormat(.jpeg)
        session.setExportScale(.x1)
        return session
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@Suite("Document package")
struct DocumentPackageTests {
    @Test("[S7-AC1] save and reopen: equal model, byte-identical render, original media bytes, schema version")
    func roundTrip() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        let session = try DocumentFixtures.styledSession()
        let document = session.document
        let url = folder.file("Test.sunshot")
        try DocumentPackage.write(document, to: url)

        let loaded = try DocumentPackage.read(from: url)
        #expect(loaded.document == document)
        #expect(loaded.document.project == document.project)
        #expect(!loaded.isReadOnly && loaded.placeholders.isEmpty)
        let before = try #require(try session.render(scale: 1))
        let after = try #require(try Renderer.render(document: loaded.document, scale: 1))
        #expect(try ImageCodec.pngData(before) == ImageCodec.pngData(after))

        let manifest = try DocumentManifestCodec.decode(Data(contentsOf: url.appendingPathComponent("document.json")))
        #expect(manifest.manifest.schemaVersion == DocumentManifest.currentSchemaVersion)
        let originals = [document.content?.data].compactMap(\.self) + document.media.values.map(\.data)
        let stored = try manifest.manifest.media.map { try Data(contentsOf: url.appendingPathComponent($0.path)) }
        #expect(Set(stored.map(DocumentFixtures.sha256)) == Set(originals.map(DocumentFixtures.sha256)))
        #expect(manifest.manifest.media.contains { $0.fileName == "sky.jpg" && $0.path.hasSuffix(".jpeg") })
    }

    @Test("[S7-AC1] generated content (no original file) is stored as PNG; empty documents save too")
    func generatedContentAndEmpty() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 40, height: 30))
        try DocumentPackage.write(session.document, to: folder.file("a.sunshot"))
        let loaded = try DocumentPackage.read(from: folder.file("a.sunshot"))
        #expect(loaded.document == session.document)
        #expect(
            try Renderer.render(document: loaded.document).map(ImageCodec.pngData)
                == session.render().map(ImageCodec.pngData))

        try DocumentPackage.write(EditorDocument(), to: folder.file("empty.sunshot"))
        #expect(try DocumentPackage.read(from: folder.file("empty.sunshot")).document == EditorDocument())
    }

    @Test("[S7-AC4] an interrupted save leaves the previous version intact; the next save replaces it")
    func atomicWrite() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        var session = try DocumentFixtures.styledSession(contentSize: 60)
        let url = folder.file("Doc.sunshot")
        try DocumentPackage.write(session.document, to: url)
        let first = session.document
        session.setCornerRadius(5)
        struct Interrupted: Error {}
        #expect(throws: Interrupted.self) {
            try DocumentPackage.write(session.document, to: url) { throw Interrupted() }
        }
        #expect(try DocumentPackage.read(from: url).document == first)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.url.path)
        #expect(leftovers == ["Doc.sunshot"])
        try DocumentPackage.write(session.document, to: url)
        #expect(try DocumentPackage.read(from: url).document.project.border.radius == 5)
    }

    // MARK: Hostile and damaged packages

    private func package(in folder: ScratchFolder, manifest: String?, media: [String: Data] = [:]) throws -> URL {
        let url = folder.file("Bad.sunshot")
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("media"), withIntermediateDirectories: true)
        if let manifest { try Data(manifest.utf8).write(to: url.appendingPathComponent("document.json")) }
        for (path, data) in media { try data.write(to: url.appendingPathComponent(path)) }
        return url
    }

    private func manifest(path: String) -> String {
        #"{"schemaVersion":1,"content":{"mediaID":"c","pixelSize":{"width":20,"height":10}},"#
            + #""media":[{"id":"c","path":"\#(path)","fileName":"shot.png"}]}"#
    }

    @Test("[S7-AC3] missing document.json, invalid JSON and plain files are refused with a reason")
    func damaged() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        #expect(throws: DocumentFormatError.missingManifest) {
            try DocumentPackage.read(from: try package(in: folder, manifest: nil))
        }
        #expect(throws: DocumentFormatError.self) {
            try DocumentPackage.read(from: try package(in: folder, manifest: "{oops"))
        }
        try Data("x".utf8).write(to: folder.file("plain.sunshot"))
        #expect(throws: DocumentFormatError.notAPackage) {
            try DocumentPackage.read(from: folder.file("plain.sunshot"))
        }
        #expect(throws: DocumentFormatError.missingManifest) {
            try DocumentPackage.read(from: folder.file("nope.sunshot"))
        }
    }

    @Test("[S7-AC3] missing or empty media is reported, and opens with a placeholder when allowed")
    func missingMedia() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        for media in [[:], ["media/c.png": Data()], ["media/c.png": Data("not an image".utf8)]] {
            let url = try package(in: folder, manifest: manifest(path: "media/c.png"), media: media)
            #expect(throws: DocumentFormatError.missingMedia(["shot.png"])) { try DocumentPackage.read(from: url) }
            let loaded = try DocumentPackage.read(from: url, allowPlaceholders: true)
            #expect(loaded.placeholders == ["shot.png"])
            #expect(loaded.document.content?.pixelSize == PixelSize(width: 20, height: 10))
            try FileManager.default.removeItem(at: url)
        }
    }

    @Test("[S7-AC3] traversal references are rejected and nothing outside the package is read")
    func traversal() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        let secret = try Fixtures.encode(try Fixtures.solid(width: 20, height: 10), as: .png)
        try secret.write(to: folder.file("x"))
        let url = try package(in: folder, manifest: manifest(path: "../../x"))
        #expect(throws: DocumentFormatError.unsafePath("../../x")) {
            try DocumentPackage.read(from: url, allowPlaceholders: true)
        }
        // A symlink inside media/ pointing outside the package is refused too.
        try FileManager.default.removeItem(at: url)
        let linked = try package(in: folder, manifest: manifest(path: "media/c.png"))
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("media/c.png"), withDestinationURL: folder.file("x"))
        #expect(throws: DocumentFormatError.unsafePath("media/c.png")) { try DocumentPackage.read(from: linked) }
    }

    @Test("[S7-AC2] a newer-schema package opens read-only")
    func newerPackage() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        let url = try package(in: folder, manifest: #"{"schemaVersion":9,"project":{"padding":7}}"#)
        let loaded = try DocumentPackage.read(from: url)
        #expect(loaded.isReadOnly && loaded.document.project.padding == 7)
    }

    @Test("[S7-AC20] reloaded documents export byte-identically at 1× and 2×")
    func exportParityAfterReload() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        var session = try DocumentFixtures.styledSession(contentSize: 200)
        try DocumentPackage.write(session.document, to: folder.file("p.sunshot"))
        let reloaded = EditorSession(document: try DocumentPackage.read(from: folder.file("p.sunshot")).document)
        for scale in [ExportScale.x1, .x2] {
            session.setExportScale(scale)
            var copy = reloaded
            copy.setExportScale(scale)
            #expect(try session.exportImageData() == copy.exportImageData())
        }
        #expect(DocumentPackage.fileExtension(for: Data("?".utf8)) == "bin")
    }
}
