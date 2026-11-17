import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

/// A controller with its own Drafts/Themes folders and UserDefaults domain.
@MainActor
struct ControllerFixture {
    let folder: TempDirectory
    let defaults: UserDefaults
    let suite: String
    let controller: DocumentController

    init(autosaveDelay: Duration = .seconds(60)) throws {
        folder = try TempDirectory()
        suite = "app.sunshot.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        controller = Self.make(folder: folder, defaults: defaults, delay: autosaveDelay)
    }

    static func make(
        folder: TempDirectory, defaults: UserDefaults, delay: Duration = .seconds(60)
    ) -> DocumentController {
        DocumentController(
            locations: DocumentLocations(drafts: folder.file("Drafts"), themes: folder.file("Themes")),
            defaults: defaults, autosaveDelay: delay)
    }

    /// A second launch on the same folders and defaults.
    func relaunch(delay: Duration = .seconds(60)) -> DocumentController {
        Self.make(folder: folder, defaults: defaults, delay: delay)
    }

    var drafts: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.file("Drafts").path)) ?? []).sorted()
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        folder.cleanUp()
    }
}

/// Polls until `condition` holds (or ~5 s pass).
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

extension MemoryHeavySuites {
    @MainActor
    @Suite("Documents: save, open, autosave, recovery", .serialized)
    struct DocumentControllerTests {
        @Test("[S7-AC1] Save As writes the package; Save writes in place; reopening restores the model")
        func saveAndOpen() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            await controller.model.importData(try TestImages.png(width: 80, height: 40))
            controller.model.perform { $0.setCornerStyle(.round) }
            #expect(controller.displayName == "Untitled" && controller.isDirty)
            #expect(await controller.save() == false)  // needs Save As first
            let url = fixture.folder.file("Test.sunshot")
            #expect(await controller.saveAs(to: url))
            #expect(controller.displayName == "Test" && !controller.isDirty && controller.fileURL == url)
            controller.model.perform { $0.setCornerRadius(80) }
            #expect(await controller.save())
            let saved = controller.model.session.document

            let other = fixture.relaunch()
            #expect(await other.openDocument(at: url))
            #expect(other.model.session.document == saved && !other.isDirty && other.model.preview != nil)
            #expect(other.recents.items.first?.url == url)
        }

        @Test("[S7-AC3] a damaged document shows \"Can't open this document\"; missing media offers placeholders")
        func openFailures() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            let bad = fixture.folder.file("Bad.sunshot")
            try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
            #expect(await controller.openDocument(at: bad) == false)
            #expect(controller.model.alert?.title == "Can't open this document")
            #expect(controller.model.alert?.message.contains("document.json") == true)

            let missing = fixture.folder.file("Missing.sunshot")
            try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
            try Data(
                (#"{"schemaVersion":1,"content":{"mediaID":"c","pixelSize":{"width":20,"height":10}},"#
                    + #""media":[{"id":"c","path":"media/c.png"}]}"#).utf8
            ).write(to: missing.appendingPathComponent("document.json"))
            #expect(await controller.openDocument(at: missing) == false)
            let offer = try #require(controller.placeholderOffer)
            #expect(offer.url == missing && offer.message.contains("missing"))
            #expect(await controller.openDocument(at: missing, allowPlaceholders: true))
            #expect(controller.model.hasContent && controller.model.notice == UIStrings.placeholdersUsed)
        }

        @Test("[S7-AC2] a newer-version document opens read-only with a notice and is never written in place")
        func readOnly() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            let url = fixture.folder.file("Future.sunshot")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let original = Data(#"{"schemaVersion":5,"project":{"padding":9}}"#.utf8)
            try original.write(to: url.appendingPathComponent("document.json"))
            #expect(await controller.openDocument(at: url))
            #expect(controller.isReadOnly && controller.model.notice == DocumentManifestCodec.newerVersionMessage)
            controller.model.perform { $0.setCornerRadius(3) }
            #expect(await controller.save() == false)
            await controller.autosave()
            #expect(try Data(contentsOf: url.appendingPathComponent("document.json")) == original)
        }

        @Test(
            "[S7-AC4] autosave after the idle delay: saved documents in place, untitled to Drafts, off the main thread")
        func autosave() async throws {
            let fixture = try ControllerFixture(autosaveDelay: .milliseconds(150))
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            let threads = ThreadLog()
            await controller.setWriteObserver { threads.append($0) }
            await controller.model.importData(try TestImages.png())
            #expect(fixture.drafts.isEmpty)  // nothing before the idle delay
            #expect(await eventually { fixture.drafts.count == 1 && !controller.isDirty })
            #expect(threads.values == [false])

            let url = fixture.folder.file("Saved.sunshot")
            #expect(await controller.saveAs(to: url))
            #expect(fixture.drafts.isEmpty)  // the draft became the saved file
            // Changes in quick succession restart the timer and produce one write.
            for radius in [10.0, 20, 30] { controller.model.perform { $0.setCornerRadius(radius) } }
            #expect(await eventually { !controller.isDirty })
            #expect(try DocumentPackage.read(from: url).document.project.border.radius == 30)
            #expect(threads.values.allSatisfy { !$0 })
        }

        @Test("[S7-AC4] autosaving a 20 MB document doesn't stall the main actor")
        func autosaveLargeMedia() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            await controller.model.importData(try TestImages.png(width: 2600, height: 2000))
            let big = Data(count: 20 * 1_048_576)
            let image = try TestImages.solid(width: 4, height: 4)
            controller.model.perform { session in
                session.setBackdropImage(image, data: big, fileName: "big.bin")
            }
            let clock = ContinuousClock()
            let save = Task { await controller.autosave() }
            var longest = Duration.zero
            var last = clock.now
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(5))
                longest = max(longest, clock.now - last)
                last = clock.now
                if !controller.isDirty { break }
            }
            await save.value
            #expect(fixture.drafts.count == 1)
            #expect(longest < .milliseconds(250), "main actor blocked for \(longest)")
        }

        @Test("[S7-AC5] an untitled draft is restored after a force-quit; empty untitled documents leave no draft")
        func recovery() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            await controller.model.importData(try TestImages.png(width: 50, height: 30))
            controller.model.perform { $0.setShadowStyle(.hug) }
            await controller.autosave()
            let document = controller.model.session.document
            // Force-quit: no close. Next launch:
            let relaunched = fixture.relaunch()
            #expect(await relaunched.recoverDraft())
            #expect(relaunched.model.session.document == document)
            #expect(relaunched.displayName == "Untitled" && relaunched.fileURL == nil && !relaunched.isDirty)

            // Closing it with Don't Save removes the draft; an empty document never writes one.
            await relaunched.close(discardChanges: true)
            #expect(fixture.drafts.isEmpty)
            await relaunched.newDocument()
            relaunched.model.perform { $0.setCornerRadius(5) }
            await relaunched.autosave()
            await relaunched.close(discardChanges: false)
            #expect(fixture.drafts.isEmpty)
            #expect(await fixture.relaunch().recoverDraft() == false)
        }

        @Test("[S7-AC19] only never-saved documents with content prompt on close; saved ones save silently")
        func closeBehaviour() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            #expect(!controller.needsSavePrompt)
            await controller.model.importData(try TestImages.png())
            #expect(controller.needsSavePrompt)
            #expect(UIStrings.saveChangesTitle(controller.displayName) == "Save changes to Untitled?")
            let url = fixture.folder.file("Closing.sunshot")
            #expect(await controller.saveAs(to: url))
            #expect(!controller.needsSavePrompt)
            controller.model.perform { $0.setCornerRadius(77) }
            await controller.close(discardChanges: false)
            #expect(try DocumentPackage.read(from: url).document.project.border.radius == 77)
        }

        @Test("[S7-AC19] with the close prompt turned off, unsaved untitled documents are discarded unasked")
        func closeWithoutAsking() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            controller.settings.askToSaveOnClose = false
            #expect(!controller.discardsWithoutAsking)
            await controller.model.importData(try TestImages.png())
            #expect(!controller.needsSavePrompt && controller.discardsWithoutAsking)
            #expect(fixture.relaunch().settings.askToSaveOnClose == false)
            await controller.close(discardChanges: controller.discardsWithoutAsking)
            #expect(fixture.drafts.isEmpty)
            controller.settings.askToSaveOnClose = true
        }

        @Test("[S7-AC6] Open Recent: 10 most recent first, missing files alert and are removed, Clear Menu empties")
        func openRecent() async throws {
            let fixture = try ControllerFixture()
            defer { fixture.cleanUp() }
            let controller = fixture.controller
            for index in 1...12 {
                #expect(await controller.saveAs(to: fixture.folder.file("Doc\(index).sunshot")))
            }
            let relaunched = fixture.relaunch()
            #expect(relaunched.recents.items.map(\.name) == (3...12).reversed().map { "Doc\($0)" })
            let gone = try #require(relaunched.recents.items.first { $0.name == "Doc7" })
            try FileManager.default.removeItem(at: gone.url)
            #expect(await relaunched.openRecent(gone) == false)
            #expect(relaunched.model.alert?.title == "File not found")
            #expect(!relaunched.recents.items.contains { $0.name == "Doc7" })
            let first = try #require(relaunched.recents.items.last)
            #expect(await relaunched.openRecent(first))
            #expect(relaunched.recents.items.first?.name == first.name)
            relaunched.clearRecents()
            #expect(relaunched.recents.items.isEmpty && fixture.relaunch().recents.items.isEmpty)
        }
    }
}

/// Thread-safe list of booleans written from the writer actor.
final class ThreadLog: @unchecked Sendable {
    // SAFETY: (test helper) all access goes through `lock`.
    private let lock = NSLock()
    private var stored: [Bool] = []

    func append(_ value: Bool) { lock.withLock { stored.append(value) } }
    var values: [Bool] { lock.withLock { stored } }
}
