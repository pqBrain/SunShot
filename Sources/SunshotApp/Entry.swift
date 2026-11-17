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
            let image = try Renderer.render(project: Project(), content: SampleContent.image(), scale: 2)
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
