import Foundation
import SunshotCore
import SunshotRender
import SwiftUI

/// Process entry point. `--smoke-test` renders a sample headlessly into the (sandboxed) temp directory, prints
/// `smoke-test ok <W>x<H> <path>` and exits; otherwise launches the UI.
@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--smoke-test") {
            exit(SmokeTest.run(directory: FileManager.default.temporaryDirectory))
        }
        SunshotApplication.main()
    }
}

enum SmokeTest {
    /// Returns a process exit code: 0 on success.
    static func run(directory: URL) -> Int32 {
        do {
            // The backdrop catalogs must load from inside the packaged, sandboxed app and render.
            let presets = try BackdropCatalog.gradientPresets()
            let wallpapers = try BackdropCatalog.wallpapers()
            let swatches = try BackdropCatalog.swatchGroups().flatMap(\.swatches)
            let tile = PixelSize(width: 64, height: 40)
            guard let preset = presets.first, let wallpaper = wallpapers.first else {
                throw BackdropCatalogError.invalid("empty catalog")
            }
            for backdrop in [Backdrop.gradient(preset.spec), .image(.wallpaper(wallpaper))] {
                _ = try Renderer.renderBackdrop(backdrop, size: tile)
            }
            FileHandle.standardOutput.write(
                Data(
                    "smoke-test backdrops \(swatches.count) swatches \(presets.count) gradients \(wallpapers.count) wallpapers\n"
                        .utf8))
            var session = EditorSession()
            session.setContent(try SampleContent.image())
            guard let image = try session.render(scale: 2) else { throw RenderError.noContent }
            let output = directory.appendingPathComponent("sunshot-smoke.png")
            try ImageCodec.pngData(image).write(to: output)
            FileHandle.standardOutput.write(Data("smoke-test ok \(image.width)x\(image.height) \(output.path)\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("smoke-test failed: \(error)\n".utf8))
            return 1
        }
    }
}
