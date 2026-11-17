import Foundation
import Testing

@testable import SunshotCore

@Suite("Bulk import: files and folders")
struct BulkImportCollectorTests {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "webp"]
    private func isImage(_ url: URL) -> Bool { Self.imageExtensions.contains(url.pathExtension.lowercased()) }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sunshot-bulk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL) throws { try Data("x".utf8).write(to: url) }

    @Test("[S14-AC3] a folder adds its top-level images in Finder order; hidden, subfolders and others are skipped")
    func folder() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["shot 10.png", "shot 2.png", "notes.txt", ".hidden.png"] {
            try touch(root.appendingPathComponent(name))
        }
        let sub = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try touch(sub.appendingPathComponent("deep.png"))

        let result = BulkImportCollector.collect([root], isSupported: isImage)
        #expect(result.items.map(\.displayName) == ["shot 2.png", "shot 10.png"])
        #expect(result.skipped == 1)
        #expect(result.items.allSatisfy { $0.accessURL == root })
        #expect(BulkImportCollector.containsDirectory([root]))
    }

    @Test("[S14-AC1] files keep the chosen order, then a folder's images follow")
    func filesThenFolder() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.png")
        let b = root.appendingPathComponent("b.jpg")
        try touch(a)
        try touch(b)
        let folder = root.appendingPathComponent("more")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try touch(folder.appendingPathComponent("c.heic"))

        let result = BulkImportCollector.collect([b, a, folder], isSupported: isImage)
        #expect(result.items.map(\.displayName) == ["b.jpg", "a.png", "c.heic"])
        #expect(result.items[0].accessURL == b)
        #expect(result.skipped == 0)
        #expect(!BulkImportCollector.containsDirectory([a, b]))
    }

    @Test("[S14-AC3] an unreadable folder counts as skipped")
    func unreadableFolder() throws {
        let root = try makeFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        let result = BulkImportCollector.collect([root], isSupported: isImage)
        #expect(result.items.isEmpty)
        #expect(result.skipped == 1)
    }
}
