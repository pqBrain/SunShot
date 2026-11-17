import Foundation
import Testing

@testable import SunshotCore

@Suite("Document manifest")
struct DocumentManifestTests {
    private func fixture(_ path: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "fixtures/\(path)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    /// The model the golden v1 file describes. Fields added after v1 take their defaults.
    static var goldenProject: Project {
        var project = Project(
            canvas: .ratio(1.5), backdrop: .gradient(SunshotDefaults.gradient), padding: 80,
            border: Border(style: .round, radius: 40), shadow: Shadow(style: .hug, intensity: .high),
            export: ExportOptions(format: .jpeg, scale: .k4))
        project.backdropSettings.solidColor = RGBAColor(rgb: 0x1A2B3C)
        return project
    }

    @Test("[S7-AC2] the golden fixtures/v1/document.json decodes to the expected model")
    func goldenFixture() throws {
        let decoded = try DocumentManifestCodec.decode(fixture("v1/document.json"))
        let manifest = decoded.manifest
        #expect(!decoded.isReadOnly)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.project == Self.goldenProject)
        let id = "3C1B5E2A-0000-4000-8000-000000000002"
        #expect(manifest.content == ContentEntry(mediaID: id, pixelSize: PixelSize(width: 1000, height: 600)))
        #expect(manifest.media == [MediaEntry(id: id, path: "media/\(id).png", fileName: "window.png")])
        let theme = try #require(manifest.theme)
        #expect(theme.name == "Ocean" && theme.id == "6F1E0C1A-0000-4000-8000-000000000001")
        #expect(Set(theme.style.keys) == ["border"])
    }

    @Test("[S7-AC2] unknown keys are ignored and missing keys take their defaults")
    func tolerantDecoding() throws {
        let decoded = try DocumentManifestCodec.decode(
            json(#"{"schemaVersion":1,"extra":[1,2],"project":{"padding":10,"border":{"style":"sharp"},"x":null}}"#))
        var expected = Project(padding: 10)
        expected.border.style = .sharp
        #expect(decoded.manifest.project == expected)
        #expect(decoded.manifest.content == nil && decoded.manifest.media.isEmpty && decoded.manifest.theme == nil)
        // An empty project and no media at all is a valid, default document.
        #expect(try DocumentManifestCodec.decode(json(#"{"schemaVersion":1}"#)).manifest.project == Project())
    }

    @Test("[S7-AC2] a stored enum case replaces the default case instead of merging into it")
    func enumCasesReplace() throws {
        let stored = #"{"schemaVersion":1,"project":{"canvas":{"custom":{"_0":{"width":1200}}}}}"#
        let project = try DocumentManifestCodec.decode(json(stored)).manifest.project
        #expect(project.canvas == .custom(CustomCanvasSize(width: 1200, height: nil)))
        let solid =
            #"{"schemaVersion":1,"project":{"backdropSettings":{"image":{"file":{"_0":"#
            + #"{"id":"a","pixelSize":{"width":4,"height":3}}}}}}}"#
        let image = try DocumentManifestCodec.decode(json(solid)).manifest.project.backdropSettings.image
        #expect(image == .file(MediaReference(id: "a", fileName: nil, pixelSize: PixelSize(width: 4, height: 3))))
    }

    @Test("[S7-AC2] a newer schema opens read-only with the newer-version message")
    func newerSchemaIsReadOnly() throws {
        let decoded = try DocumentManifestCodec.decode(json(#"{"schemaVersion":2,"project":{"padding":12}}"#))
        #expect(decoded.isReadOnly)
        #expect(decoded.manifest.project.padding == 12)
        #expect(DocumentManifestCodec.newerVersionMessage == "This document was made with a newer version of Sunshot")
    }

    @Test("[S7-AC2] v1 is the first schema: migration is the identity and encoding round-trips")
    func migrationAndRoundTrip() throws {
        let manifest = DocumentManifest(
            project: Self.goldenProject, content: ContentEntry(mediaID: "c", pixelSize: PixelSize(width: 3, height: 2)),
            media: [MediaEntry(id: "c", path: "media/c.png")],
            theme: try Theme.extract(from: Self.goldenProject, name: "Paper"))
        let data = try DocumentManifestCodec.encode(manifest)
        #expect(try DocumentManifestCodec.decode(data).manifest == manifest)
        let tree = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(DocumentManifestCodec.migrate(tree, from: 1) == tree)
        #expect(DocumentManifest.currentSchemaVersion == 1)
    }

    @Test(
        "[S7-AC3] damaged manifests are refused with a reason",
        arguments: [
            ("not json", "damaged"), ("[1,2]", "damaged"), (#"{"project":{}}"#, "damaged"),
            (#"{"schemaVersion":"one"}"#, "damaged"), (#"{"schemaVersion":1,"project":{"padding":"wide"}}"#, "damaged"),
            (#"{"schemaVersion":1,"content":{"mediaID":"x","pixelSize":{"width":1,"height":1}}}"#, "missing"),
        ])
    func damagedManifest(text: String, reasonWord: String) {
        #expect {
            try DocumentManifestCodec.decode(json(text))
        } throws: { error in
            (error as? DocumentFormatError)?.reason.contains(reasonWord) == true
        }
    }

    @Test(
        "[S7-AC3] media paths that leave the package are rejected",
        arguments: [
            "../../x", "media/../../x", "media/..", "/etc/passwd", "media/sub/x.png", "media/.hidden", "x.png",
            "media/", "media\\x", "media/a:b",
        ])
    func traversalRejected(path: String) {
        #expect(throws: DocumentFormatError.unsafePath(path)) { try DocumentManifestCodec.validate(path: path) }
        let text =
            #"{"schemaVersion":1,"media":[{"id":"a","path":"\#(path.replacingOccurrences(of: "\\", with: "\\\\"))"}]}"#
        #expect(throws: DocumentFormatError.self) { try DocumentManifestCodec.decode(json(text)) }
    }

    @Test("[S7-AC3] new media paths are always safe")
    func mediaPaths() throws {
        #expect(DocumentManifestCodec.mediaPath(id: "ABC-1", fileExtension: "PNG") == "media/ABC-1.png")
        let hostile = DocumentManifestCodec.mediaPath(id: "../../etc", fileExtension: "/x")
        try DocumentManifestCodec.validate(path: hostile)
        #expect(hostile == "media/etc.x")
        #expect(DocumentManifestCodec.mediaPath(id: "..", fileExtension: "") == "media/media")
        for error in [
            DocumentFormatError.missingManifest, .invalidJSON("x"), .missingMedia(["a.png"]), .unsafePath("../x"),
            .notAPackage,
        ] {
            #expect(!error.reason.isEmpty)
        }
    }

    @Test("[S7-AC2] JSON values round-trip every kind")
    func jsonValues() throws {
        let value = JSONValue.object([
            "a": .array([.null, .bool(true), .int(3), .double(0.25), .string("x")]), "b": .object([:]),
        ])
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
        #expect(value["a"] != nil && JSONValue.int(1)["a"] == nil)
        #expect(JSONValue.int(1).merged(over: .object(["a": .int(2)])) == .int(1))
    }
}
