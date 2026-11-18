import Foundation
import Testing

@testable import SunshotPlatform

@Suite("Settings ▸ About")
struct AboutInfoTests {
    @Test("version, system and diagnostics lines")
    func lines() {
        let info = AboutInfo(
            appName: "Sunshot", version: "0.1.0", build: "42", systemVersion: "27.2.1", modelIdentifier: "Mac16,8")
        #expect(info.versionLine == "Version 0.1.0 (42)")
        #expect(info.systemLine == "macOS 27.2.1 · Mac16,8")
        let lines = info.diagnostics.split(separator: "\n").map(String.init)
        #expect(Array(lines.prefix(3)) == ["Sunshot 0.1.0 (42)", "macOS 27.2.1", "Model Mac16,8"])
        #expect(lines.count == 4 && lines[3].hasPrefix("Locale "))
    }

    @Test("unbundled placeholders and missing values fall back; the running Mac is described")
    func current() {
        #expect(AboutInfo.bundleValue("__VERSION__") == nil)
        #expect(AboutInfo.bundleValue("") == nil)
        #expect(AboutInfo.bundleValue(3) == nil)
        #expect(AboutInfo.bundleValue("1.2") == "1.2")
        let info = AboutInfo.current(bundle: Bundle(for: BundleMarker.self))
        #expect(!info.version.isEmpty && !info.build.isEmpty)
        #expect(info.systemVersion.hasPrefix("\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)."))
        #expect(AboutInfo.hardwareModel()?.isEmpty == false)
    }
}

private final class BundleMarker {}
