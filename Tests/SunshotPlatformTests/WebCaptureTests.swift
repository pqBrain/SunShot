import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotPlatform

@MainActor
struct WebKitCaptureTests {
    private static let page = """
        <html><body style="margin:0;background:#ff0000">
        <div style="height:3000px;background:linear-gradient(#ff0000,#0000ff)"></div>
        </body></html>
        """

    @Test("[S10-AC11] offscreen web view captures the viewport width and height (local HTML, no network)")
    func viewportCapture() async throws {
        let capturer = WebKitPageCapturer()
        let options = WebCaptureOptions(viewport: .phone, fullPage: false, delaySeconds: 0)
        let image = try await capturer.capture(html: Self.page, options: options)
        let scale = Double(image.width) / Double(WebViewport.phone.width)
        #expect(scale >= 1)
        #expect(abs(Double(image.height) / scale - Double(WebViewport.phone.height)) <= 1)
        #expect(try Self.topLeftPixel(image)[0] > 200, "the page's red background is in the picture")
    }

    @Test("[S10-AC13] the WebKit capturer itself refuses non-http(s) URLs")
    func refusesFileURLs() async throws {
        let capturer = WebKitPageCapturer()
        await #expect(throws: WebCaptureError.unsupportedScheme("file")) {
            try await capturer.capture(url: URL(fileURLWithPath: "/etc/hosts"), options: WebCaptureOptions())
        }
    }

    @Test("[S10-AC14] load errors map to clear reasons")
    func navigationErrors() {
        #expect(NavigationWaiter.mapped(URLError(.timedOut)) == .timedOut)
        #expect(NavigationWaiter.mapped(URLError(.cancelled)) == .cancelled)
        if case .loadFailed = NavigationWaiter.mapped(URLError(.notConnectedToInternet)) {
        } else {
            Issue.record("offline should be a load failure")
        }
    }

    private static func topLeftPixel(_ image: CGImage) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Draw so the image's top-left pixel lands on the 1×1 context.
            context.draw(image, in: CGRect(x: 0, y: -(image.height - 1), width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return pixel
    }

    @Test("[S10-AC12] full-page capture grows to the page height")
    func fullPageCapture() async throws {
        let capturer = WebKitPageCapturer()
        let options = WebCaptureOptions(viewport: .phone, fullPage: true, delaySeconds: 0)
        let image = try await capturer.capture(html: Self.page, options: options)
        let scale = Double(image.width) / Double(WebViewport.phone.width)
        #expect(abs(Double(image.height) / scale - 3000) <= 2)
    }
}
