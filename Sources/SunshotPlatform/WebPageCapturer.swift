import AppKit
public import CoreGraphics
public import Foundation
public import SunshotCore
import WebKit
import os

/// Loads a web page offscreen and returns a picture of it (S10). A protocol so capture flows are testable
/// without a network or a real web view.
public protocol WebPageCapturing: Sendable {
    @MainActor func capture(url: URL, options: WebCaptureOptions) async throws -> CGImage
}

/// The WebKit capturer: an offscreen `WKWebView` with a private, non-persistent data store (no cookies or cache
/// are kept), laid out at the viewport width. Full-page captures scroll through the page first so lazy-loaded
/// images load, then grow the view to the page height (capped at `WebCaptureOptions.maxPageHeight`).
@MainActor
public final class WebKitPageCapturer: WebPageCapturing {
    private static let logger = Logger(subsystem: "app.sunshot", category: "web-capture")

    public init() {}

    public func capture(url: URL, options: WebCaptureOptions) async throws -> CGImage {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw WebCaptureError.unsupportedScheme(url.scheme ?? "")
        }
        let request = URLRequest(url: url, timeoutInterval: options.clampedTimeout)
        return try await capture(options: options) { $0.load(request) }
    }

    /// Test seam: renders an HTML string (no network). Not reachable from the UI, which only passes http(s) URLs.
    func capture(html: String, options: WebCaptureOptions) async throws -> CGImage {
        try await capture(options: options) { $0.loadHTMLString(html, baseURL: nil) }
    }

    private func capture(options: WebCaptureOptions, load: (WKWebView) -> WKNavigation?) async throws -> CGImage {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        let viewport = CGRect(x: 0, y: 0, width: options.viewport.width, height: options.viewport.height)
        let webView = WKWebView(frame: viewport, configuration: configuration)
        // An offscreen window gives WebKit a backing store to paint into; it is never shown.
        let window = NSWindow(
            contentRect: viewport.offsetBy(dx: -30000, dy: -30000), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            window.contentView = nil
            window.close()
        }

        try await waiter.wait {
            _ = load(webView)
        } onCancel: {
            webView.stopLoading()
        }
        var height = Double(options.viewport.height)
        if options.fullPage {
            await scrollThrough(webView)
            let contentHeight = try await pageHeight(of: webView)
            height = Double(options.captureHeight(contentHeight: contentHeight))
            let full = CGRect(x: 0, y: 0, width: viewport.width, height: height)
            window.setContentSize(full.size)
            webView.frame = full
        }
        try await Task.sleep(for: .seconds(options.clampedDelay))
        try Task.checkCancellation()

        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = CGRect(x: 0, y: 0, width: viewport.width, height: height)
        snapshot.afterScreenUpdates = true
        let image: NSImage
        do {
            image = try await webView.takeSnapshot(configuration: snapshot)
        } catch {
            Self.logger.error("snapshot failed: \(error.localizedDescription, privacy: .public)")
            throw WebCaptureError.snapshotFailed
        }
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw WebCaptureError.snapshotFailed
        }
        return cgImage
    }

    /// Scrolls to the bottom in screen-sized steps and back to the top, so lazy-loaded content appears.
    private func scrollThrough(_ webView: WKWebView) async {
        let script = """
            const step = Math.max(window.innerHeight, 200);
            const limit = Math.min(document.documentElement.scrollHeight, \(WebCaptureOptions.maxPageHeight));
            for (let y = 0; y < limit; y += step) {
                window.scrollTo(0, y);
                await new Promise(r => setTimeout(r, 60));
            }
            window.scrollTo(0, 0);
            return true;
            """
        _ = try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)
    }

    private func pageHeight(of webView: WKWebView) async throws -> Double {
        let script = """
            return Math.max(document.body ? document.body.scrollHeight : 0,
                document.documentElement.scrollHeight, document.documentElement.offsetHeight);
            """
        let value = try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)
        return (value as? NSNumber)?.doubleValue ?? Double(webView.frame.height)
    }
}

/// Bridges one page load to async/await: resumes exactly once with success, a load error, or cancellation.
@MainActor
final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func wait(start: () -> Void, onCancel: @escaping @MainActor () -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: WebCaptureError.cancelled)
                    return
                }
                self.continuation = continuation
                start()
            }
        } onCancel: {
            Task { @MainActor in
                onCancel()
                self.finish(.failure(WebCaptureError.cancelled))
            }
        }
    }

    func finish(_ result: Result<Void, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        finish(.failure(Self.mapped(error)))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error
    ) {
        finish(.failure(Self.mapped(error)))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(WebCaptureError.loadFailed("the page stopped responding")))
    }

    static func mapped(_ error: any Error) -> WebCaptureError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut { return .timedOut }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return .cancelled }
        return .loadFailed(nsError.localizedDescription)
    }
}
