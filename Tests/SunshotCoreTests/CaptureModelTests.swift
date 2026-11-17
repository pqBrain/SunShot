import Foundation
import SunshotCore
import Testing

@Suite("Capture model")
struct CaptureModelTests {
    @Test("[S10-AC13] http(s) addresses are accepted; https is added when no scheme is typed")
    func acceptedAddresses() throws {
        #expect(try WebCaptureURL.parse("example.com").absoluteString == "https://example.com")
        #expect(try WebCaptureURL.parse("  https://example.com/a?b  ").absoluteString == "https://example.com/a?b")
        #expect(try WebCaptureURL.parse("http://localhost:8080").absoluteString == "http://localhost:8080")
        #expect(try WebCaptureURL.parse("localhost:8080/x").absoluteString == "https://localhost:8080/x")
        #expect(try WebCaptureURL.parse("HTTPS://Example.com").scheme?.lowercased() == "https")
        #expect(try WebCaptureURL.parse("sub.example.co.uk/path").host == "sub.example.co.uk")
    }

    @Test("[S10-AC13] empty, spaced, non-http and hostless addresses are refused with a reason")
    func refusedAddresses() {
        let cases: [(String, WebCaptureError)] = [
            ("", .emptyURL), ("   ", .emptyURL), ("exa mple.com", .invalidURL),
            ("file:///etc/hosts", .unsupportedScheme("file")),
            ("javascript:alert(1)", .unsupportedScheme("javascript")),
            ("data:text/html,<b>x</b>", .unsupportedScheme("data")), ("ftp://x.com", .unsupportedScheme("ftp")),
            ("https://", .invalidURL), ("notahost", .invalidURL), ("https://.com", .invalidURL),
        ]
        for (text, expected) in cases {
            #expect(throws: expected, "\(text)") { try WebCaptureURL.parse(text) }
        }
        let reasons: [WebCaptureError] = [
            .emptyURL, .invalidURL, .unsupportedScheme("file"), .timedOut, .loadFailed("x"), .snapshotFailed,
            .cancelled,
        ]
        #expect(Set(reasons.map(\.reason)).count == reasons.count)
        #expect(WebCaptureError.timedOut.reason == "The page took too long to load.")
        #expect(WebCaptureError.unsupportedScheme("file").reason.contains("file:"))
    }

    @Test("[S10-AC14] delay is limited to 0…10 s; the timeout is at least 1 s")
    func delayAndTimeout() {
        #expect(WebCaptureOptions(delaySeconds: -3).clampedDelay == 0)
        #expect(WebCaptureOptions(delaySeconds: 25).clampedDelay == WebCaptureOptions.maxDelaySeconds)
        #expect(WebCaptureOptions(delaySeconds: .nan).clampedDelay == 0)
        #expect(WebCaptureOptions(delaySeconds: 2).clampedDelay == 2)
        #expect(WebCaptureOptions(timeoutSeconds: 0.2).clampedTimeout == 1)
        #expect(WebCaptureOptions(timeoutSeconds: -1).clampedTimeout == WebCaptureOptions.defaultTimeoutSeconds)
        #expect(WebCaptureOptions().viewport == .desktop && !WebCaptureOptions().fullPage)
    }

    @Test("[S10-AC12] full-page height is the page height, at least the viewport, at most 16,000 px")
    func captureHeight() {
        let full = WebCaptureOptions(viewport: .phone, fullPage: true)
        #expect(full.captureHeight(contentHeight: 3000) == 3000)
        #expect(full.captureHeight(contentHeight: 100) == WebViewport.phone.height)
        #expect(full.captureHeight(contentHeight: 99_999) == WebCaptureOptions.maxPageHeight)
        #expect(full.captureHeight(contentHeight: .infinity) == WebViewport.phone.height)
        #expect(WebCaptureOptions(viewport: .laptop).captureHeight(contentHeight: 3000) == 800)
        let sizes = WebViewport.allCases.map { "\($0.width)x\($0.height)" }
        #expect(sizes == ["1440x900", "1280x800", "834x1112", "390x844"])
    }

    @Test("[S10-AC15] area selection: normalised, limited to the display, ≥ 8 pt, pixel size × scale")
    func areaSelection() {
        let rect = AreaSelection.rect(from: (300, 200), to: (100, 50), displayWidth: 1512, displayHeight: 982)
        #expect(rect == LayoutRect(x: 100, y: 50, width: 200, height: 150))
        let clamped = AreaSelection.rect(from: (-50, -50), to: (2000, 2000), displayWidth: 1512, displayHeight: 982)
        #expect(clamped == LayoutRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(AreaSelection.isCapturable(rect))
        #expect(!AreaSelection.isCapturable(LayoutRect(x: 0, y: 0, width: 7, height: 100)))
        #expect(AreaSelection.pixelSize(of: rect, scale: 2) == PixelSize(width: 400, height: 300))
        #expect(AreaSelection.pixelSize(of: rect, scale: .nan) == PixelSize(width: 200, height: 150))
    }

    @Test("[S10-AC15] the window list leaves out Sunshot and tiny windows, sorted by app then title")
    func pickableWindows() {
        let windows = [
            CapturableWindow(id: 1, title: "Notes", appName: "Zed", width: 800, height: 600),
            CapturableWindow(id: 2, title: "", appName: "Sunshot", width: 800, height: 600),
            CapturableWindow(id: 3, title: "b", appName: "Atlas", width: 900, height: 700),
            CapturableWindow(id: 4, title: "a", appName: "atlas", width: 900, height: 700),
            CapturableWindow(id: 5, title: "Item", appName: "Menu", width: 30, height: 22),
        ]
        let pickable = CapturableWindow.pickable(windows, excludingApp: "Sunshot")
        #expect(pickable.map(\.id) == [4, 3, 1])
        #expect(windows[0].displayName == "Zed — Notes")
        #expect(windows[1].displayName == "Sunshot")
    }

    @Test("[S10-AC16] permission and failure messages are clear")
    func screenErrors() {
        #expect(ScreenCaptureError.permissionDenied.reason.contains("Screen & System Audio Recording"))
        #expect(ScreenCaptureError.permissionDenied.title != ScreenCaptureError.noDisplay.title)
        let all: [ScreenCaptureError] = [
            .permissionDenied, .noDisplay, .windowNotFound, .selectionTooSmall, .failed("x"),
        ]
        #expect(Set(all.map(\.reason)).count == all.count)
    }

    @Test("[S10-AC10] the manifest round-trips a crop; a missing crop key decodes as no crop")
    func manifestCrop() throws {
        let manifest = DocumentManifest(crop: CropRect(x: 1, y: 2, width: 30, height: 40))
        let data = try DocumentManifestCodec.encode(manifest)
        #expect(try DocumentManifestCodec.decode(data).manifest.crop == manifest.crop)
        let old = Data(#"{"schemaVersion": 1, "project": {}}"#.utf8)
        #expect(try DocumentManifestCodec.decode(old).manifest.crop == nil)
    }

    @Test("[S10-AC17] the global capture shortcut is off by default")
    func hotkeyDefault() {
        #expect(AppSettings().captureHotkeyEnabled == false)
        #expect(AppSettings.defaults.captureHotkeyEnabled == false)
    }
}
