import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing
import UniformTypeIdentifiers

@testable import SunshotPlatform

extension MemoryHeavySuites {
    @MainActor
    @Suite("Export and pasteboard", .serialized)
    struct ExportAndPasteboardTests {
        @Test("[S1-AC10] export at 1× writes a valid PNG of canvas size; the name follows the default template")
        func export() async throws {
            let directory = try TempDirectory()
            defer { directory.cleanUp() }
            let model = EditorModel()
            await model.importData(try TestImages.png(width: 1000, height: 600))
            await model.perform { $0.setExportScale(.x1) }.value
            let url = directory.file("out.png")
            await model.export(to: url)
            #expect(model.alert == nil)
            let image = try ImageCodec.decode(Data(contentsOf: url))
            #expect((image.width, image.height) == (1128, 728))

            let name = model.suggestedExportName(now: Date(timeIntervalSince1970: 0))
            #expect(
                name.range(
                    of: #"^screenshot_1x_sunshot_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.png$"#,
                    options: .regularExpression)
                    != nil)
        }

        @Test("[S1-AC11] write failure leaves no file, shows \"Couldn't export the image\", document intact")
        func exportFailure() async throws {
            let directory = try TempDirectory()
            defer { directory.cleanUp() }
            let model = EditorModel()
            await model.importData(try TestImages.png())
            let before = model.session.document
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.url.path)
            let url = directory.file("out.png")

            await model.export(to: url)
            #expect(model.alert?.title == "Couldn't export the image")
            #expect(model.alert?.message.isEmpty == false)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
            #expect(leftovers.isEmpty)
            #expect(model.session.document == before)
            await model.clearContent()
            #expect(!model.hasContent)
        }

        @Test("[S1-AC12] copy puts exactly one PNG on the pasteboard, pixel-identical to the export")
        func copy() async throws {
            try await withPrivatePasteboard { pasteboard in
                let model = EditorModel()
                await model.importData(try TestImages.png(width: 300, height: 200))
                await model.perform { $0.setExportScale(.x1) }.value
                pasteboard.setString("stale", forType: .string)
                await model.copyPNG(to: pasteboard)
                // One item whose (only written) representation is PNG; AppKit may advertise lazy conversions of it.
                let items = try #require(pasteboard.pasteboardItems)
                #expect(items.count == 1)
                #expect(items.first?.types.first == .png)
                #expect(pasteboard.string(forType: .string) == nil)
                let copied = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
                let exported = try ImageCodec.decode(try await model.pngData())
                #expect((copied.width, copied.height) == (428, 328))
                #expect(copied.dataProvider?.data as Data? == exported.dataProvider?.data as Data?)
            }
        }

        @Test("[S1-AC12] copying with no content shows the export alert and leaves the pasteboard alone")
        func copyEmpty() async throws {
            await withPrivatePasteboard { pasteboard in
                let model = EditorModel()
                pasteboard.clearContents()
                pasteboard.setString("keep", forType: .string)
                await model.copyPNG(to: pasteboard)
                #expect(model.alert?.title == EditorModel.exportFailedTitle)
                #expect(pasteboard.string(forType: .string) == "keep")
            }
        }

        @Test("[S1-AC5] paste imports PNG, TIFF or an image file URL; ignores pasteboards without images")
        func paste() async throws {
            let directory = try TempDirectory()
            defer { directory.cleanUp() }
            try await withPrivatePasteboard { pasteboard in
                let model = EditorModel()
                pasteboard.clearContents()
                pasteboard.setString("text only", forType: .string)
                #expect(!model.canPaste(from: pasteboard))
                await model.paste(from: pasteboard)
                #expect(!model.hasContent)

                pasteboard.clearContents()
                pasteboard.setData(try TestImages.png(width: 12, height: 12), forType: .png)
                #expect(model.canPaste(from: pasteboard))
                await model.paste(from: pasteboard)
                #expect(model.session.document.content?.pixelSize == PixelSize(width: 12, height: 12))

                pasteboard.clearContents()
                let tiff = try TestImages.encode(TestImages.solid(width: 14, height: 14), as: .tiff)
                pasteboard.setData(tiff, forType: .tiff)
                await model.paste(from: pasteboard)
                #expect(model.session.document.content?.pixelSize == PixelSize(width: 14, height: 14))

                let file = directory.file("clip.png")
                try TestImages.png(width: 16, height: 16).write(to: file)
                pasteboard.clearContents()
                pasteboard.writeObjects([file as NSURL])
                #expect(model.canPaste(from: pasteboard))
                await model.paste(from: pasteboard)
                #expect(model.session.document.content?.pixelSize == PixelSize(width: 16, height: 16))
                #expect(model.session.history.undoNames.last == "Replace Image")
            }
        }

        @Test("[S1-AC17] 8000×8000 import/preview/export: main actor stays responsive, 8128² output, memory ≤ 1.5 GB")
        func largeImage() async throws {
            let directory = try TempDirectory()
            defer { directory.cleanUp() }
            let data = try TestImages.png(width: 8000, height: 8000)
            let model = EditorModel()
            let baseline = memoryFootprint()
            var peak = baseline
            var longestGap: Duration = .zero
            let clock = ContinuousClock()
            let heartbeat = Task { @MainActor in
                var last = clock.now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                    let now = clock.now
                    longestGap = max(longestGap, now - last)
                    last = now
                    peak = max(peak, memoryFootprint())
                }
            }
            await model.importData(data)
            await model.perform { $0.setExportScale(.x1) }.value
            for attempt in 1...2 {
                await model.export(to: directory.file("big-\(attempt).png"))
            }
            heartbeat.cancel()

            #expect(model.alert == nil)
            let exported = try ImageCodec.decode(Data(contentsOf: directory.file("big-2.png")))
            #expect((exported.width, exported.height) == (8128, 8128))
            #expect(longestGap < .milliseconds(100), "main actor blocked for \(longestGap)")
            let growthGB = Double(peak &- baseline) / 1_073_741_824
            #expect(growthGB <= 1.5, "memory grew by \(growthGB) GB")
        }
    }
}
