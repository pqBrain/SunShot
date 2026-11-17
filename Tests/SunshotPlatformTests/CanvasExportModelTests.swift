import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing
import UniformTypeIdentifiers

@testable import SunshotPlatform

extension MemoryHeavySuites {
    @MainActor
    @Suite("Canvas size and export options (model)", .serialized)
    struct CanvasExportModelTests {
        private func loaded(width: Int = 1000, height: Int = 600) async throws -> EditorModel {
            let model = EditorModel()
            await model.importData(try TestImages.png(width: width, height: height))
            return model
        }

        private func preset(_ id: String) throws -> CanvasPreset {
            try #require(CanvasPresetLibrary.shared.catalog?.preset(id: id))
        }

        @Test("[S4-AC1] the canvas control reads Auto with the content + 64 px size")
        func canvasControl() async throws {
            let model = try await loaded()
            #expect(UIStrings.canvasValue(model.project.canvas) == "Auto")
            #expect(
                UIStrings.canvasSizeAccessibility(model.project.canvas, size: model.session.canvasSize)
                    == "Canvas size: Auto, 1128 by 728 pixels")
            #expect(UIStrings.canvasValue(.custom(CustomCanvasSize(width: 800, height: nil))) == "Custom 800 × Auto")
            #expect(UIStrings.canvasValue(.preset(try preset("store.iphone-6-7"))) == "iPhone 6.7″")
            #expect(UIStrings.canvasValue(.preset(try preset("general.widescreen"))) == "16:9 Widescreen")
        }

        @Test("[S4-AC3] the library groups search results; no match shows \"No sizes match\"")
        func librarySearch() {
            let library = CanvasPresetLibrary.shared
            #expect(library.presets.count >= 25)
            #expect(library.sections(matching: "zzzz").isEmpty && UIStrings.noSizesMatch == "No sizes match")
            #expect(library.sections(matching: "").map(\.group.name) == ["General", "Social", "App stores"])
        }

        @Test("[S4-AC6] typed custom size: invalid input is refused with no undo entry, valid input applies")
        func customSize() async throws {
            let model = try await loaded()
            let undoCount = model.session.history.undoCount
            #expect(!model.setCustomCanvas(width: "abc", height: "100"))
            #expect(!model.setCustomCanvas(width: "20000", height: ""))
            #expect(model.session.history.undoCount == undoCount && model.project.canvas == .auto)
            #expect(UIStrings.customSizeInvalid == "Enter 1–16384")
            #expect(model.setCustomCanvas(width: "1200", height: ""))
            #expect(model.session.canvasSize == PixelSize(width: 1200, height: 774))
        }

        @Test("[S4-AC8] the preview follows the canvas at once; undo restores it")
        func previewFollowsCanvas() async throws {
            let model = try await loaded()
            let wide = try preset("general.widescreen")
            await model.perform { $0.selectCanvasPreset(wide) }.value
            let preview = try #require(model.preview)
            #expect((preview.width, preview.height) == (1294, 728))
            #expect(model.undoTitle.contains("Change Canvas Size"))
            await model.undo()
            #expect(model.project.canvas == .auto)
            #expect(model.preview.map { ($0.width, $0.height) } ?? (0, 0) == (1128, 728))
        }

        @Test("[S4-AC9] format row shows the extension; only writable formats are offered")
        func formatRow() async throws {
            let model = try await loaded()
            #expect(model.availableFormats == ImageCodec.writableFormats)
            #expect(model.availableFormats.contains(.png) && model.availableFormats.contains(.heic))
            for format in model.availableFormats {
                await model.perform { $0.setExportFormat(format) }.value
                #expect(model.formatText == ".\(format.fileExtension)")
                #expect(model.project.export.format == format)
            }
            let expected = ["png": ".png", "jpeg": ".jpg", "heic": ".heic", "webp": ".webp"]
            for format in ExportFormat.allCases { #expect(expected[format.rawValue] == ".\(format.fileExtension)") }
        }

        @Test("[S4-AC10] the JPEG transparency notice appears only for JPEG over a transparent backdrop")
        func jpegNotice() async throws {
            let model = try await loaded()
            await model.perform { $0.setExportFormat(.jpeg) }.value
            #expect(model.exportNotice == nil, "the default backdrop is opaque")
            await model.perform { $0.setBackdropKind(.none) }.value
            #expect(model.exportNotice == "JPEG doesn't support transparency")
            await model.perform { $0.setExportFormat(.png) }.value
            #expect(model.exportNotice == nil)
        }

        @Test("[S4-AC11] the Resolution row shows the output size before exporting")
        func resolutionRow() async throws {
            let model = try await loaded()
            let expected: [(ExportScale, String)] = [
                (.x1, "1128 × 728"), (.x2, "2256 × 1456"), (.k4, "3840 × 2478"), (.k6, "6144 × 3965"),
            ]
            for (scale, text) in expected {
                await model.perform { $0.setExportScale(scale) }.value
                #expect(model.resolutionText == text)
            }
        }

        @Test("[S4-AC12] too large: the popover says so, Export is disabled, and an attempt writes nothing")
        func tooLarge() async throws {
            let directory = try TempDirectory()
            defer { directory.cleanUp() }
            let model = try await loaded(width: 64, height: 64)
            await model.perform { $0.setExportScale(.x1) }.value
            #expect(model.setCustomCanvas(width: "16384", height: "16384"))
            #expect(model.exportProblem == nil && model.canExport, "16384² at 1× is exactly the limit")
            await model.perform { $0.setExportScale(.x2) }.value
            #expect(model.exportProblem == "This size is too large to export (max 16384 px per side)")
            #expect(!model.canExport)
            let url = directory.file("big.png")
            await model.export(to: url)
            #expect(model.alert?.message == UIStrings.exportTooLarge)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            await model.perform { $0.setExportScale(.k6) }.value
            #expect(model.exportProblem == nil && model.resolutionText == "6144 × 6144")
        }

        @Test("[S4-AC16] the Export button title follows scale, format and store sizes, and is spoken in full")
        func buttonTitle() async throws {
            let model = try await loaded()
            let phone = try preset("store.iphone-6-7")
            #expect(model.exportButtonTitle == "Export 2× • PNG")
            await model.perform {
                $0.setExportScale(.k4)
                $0.setExportFormat(.jpeg)
            }.value
            #expect(model.exportButtonTitle == "Export 4K • JPEG")
            #expect(model.exportAccessibilityLabel == "Export at 4K as JPEG, ⇧⌘E")
            await model.perform {
                $0.setExportFormat(.png)
                $0.selectCanvasPreset(phone)
            }.value
            #expect(model.exportButtonTitle == "Export 1290×2796 • PNG")
            #expect(model.exportAccessibilityLabel == "Export at 1290 by 2796 pixels as PNG, ⇧⌘E")
            #expect(!model.isScaleSelectable && model.resolutionText == "1290 × 2796")
            #expect(model.suggestedExportName(now: Date(timeIntervalSince1970: 0)).hasPrefix("screenshot_1x_"))
        }

        @Test("[S4-AC17] HEIC at 2×: suggested name ends .heic and the file is 2256×1456 HEIC (temp dir only)")
        func exportHEIC() async throws {
            let directory = try TempDirectory()
            defer { directory.cleanUp() }
            let model = try await loaded()
            await model.perform { $0.setExportFormat(.heic) }.value
            let name = model.suggestedExportName(random: { "r4nd0m" })
            #expect(
                name.range(
                    of: #"^screenshot_2x_sunshot_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.heic$"#,
                    options: .regularExpression)
                    != nil, "\(name)")
            #expect(model.exportContentType == .heic)
            let url = directory.file(name)
            await model.export(to: url)
            #expect(model.alert == nil)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.heic")
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect((image.width, image.height) == (2256, 1456))
        }

        @Test("[S4-AC18] ⌘C with JPEG at 4K puts a PNG of the 4K size on the pasteboard, never a JPEG")
        func copyHonoursScale() async throws {
            try await withPrivatePasteboard { pasteboard in
                let model = try await loaded()
                await model.perform {
                    $0.setExportFormat(.jpeg)
                    $0.setExportScale(.k4)
                }.value
                await model.copyPNG(to: pasteboard)
                #expect(model.alert == nil)
                #expect(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) == nil)
                let image = try ImageCodec.decode(try #require(pasteboard.data(forType: .png)))
                #expect((image.width, image.height) == (3840, 2478))
            }
        }

        @Test("[S4-AC20] size and export controls have spoken labels; preset tiles read ratio, name and size")
        func accessibilityLabels() async throws {
            let model = try await loaded(width: 1792, height: 952)
            let wide = try preset("general.widescreen")
            #expect(
                UIStrings.presetAccessibility(wide, size: model.canvasSize(for: wide))
                    == "16:9 Widescreen, 1920 by 1080")
            let phone = try preset("store.iphone-6-7")
            #expect(
                UIStrings.presetAccessibility(phone, size: model.canvasSize(for: phone)) == "iPhone 6.7″, 1290 by 2796")
            #expect(UIStrings.presetAccessibilityAuto(size: PixelSize(width: 1920, height: 1080)).hasPrefix("Auto"))
            let labels = [
                UIStrings.searchSizes, UIStrings.widthAccessibility, UIStrings.heightAccessibility,
                UIStrings.formatPicker,
                UIStrings.scalePicker, UIStrings.exportOptionsAccessibility, UIStrings.clearSearch,
            ]
            #expect(labels.allSatisfy { !$0.isEmpty })
            #expect(ExportScale.allCases.map(\.spokenName) == ["1 times", "2 times", "4K", "6K"])
        }
    }
}
