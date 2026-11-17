public import Foundation

/// Viewport presets for website capture (S10): the page is laid out at `width` × `height` CSS pixels.
public enum WebViewport: String, CaseIterable, Codable, Hashable, Sendable {
    case desktop, laptop, tablet, phone

    public var width: Int {
        switch self {
        case .desktop: 1440
        case .laptop: 1280
        case .tablet: 834
        case .phone: 390
        }
    }

    public var height: Int {
        switch self {
        case .desktop: 900
        case .laptop: 800
        case .tablet: 1112
        case .phone: 844
        }
    }
}

/// How a website is captured.
public struct WebCaptureOptions: Codable, Hashable, Sendable {
    /// Longest page a full-page capture keeps, in CSS pixels (longer pages are cut off at this height).
    public static let maxPageHeight = 16000
    public static let maxDelaySeconds = 10.0
    public static let defaultTimeoutSeconds = 30.0

    public var viewport: WebViewport
    /// Capture the whole scrollable page instead of the first screen.
    public var fullPage: Bool
    /// Extra wait after the page has loaded (animations, late content), 0…10 s.
    public var delaySeconds: Double
    /// Loading longer than this fails with `WebCaptureError.timedOut`.
    public var timeoutSeconds: Double

    public init(
        viewport: WebViewport = .desktop, fullPage: Bool = false, delaySeconds: Double = 1,
        timeoutSeconds: Double = WebCaptureOptions.defaultTimeoutSeconds
    ) {
        self.viewport = viewport
        self.fullPage = fullPage
        self.delaySeconds = delaySeconds
        self.timeoutSeconds = timeoutSeconds
    }

    /// The delay limited to 0…`maxDelaySeconds`.
    public var clampedDelay: Double {
        guard delaySeconds.isFinite else { return 0 }
        return min(max(delaySeconds, 0), Self.maxDelaySeconds)
    }

    /// The timeout, at least one second (default when not a finite number).
    public var clampedTimeout: Double {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else { return Self.defaultTimeoutSeconds }
        return max(timeoutSeconds, 1)
    }

    /// Height of the captured area for a page whose document is `contentHeight` CSS pixels tall.
    public func captureHeight(contentHeight: Double) -> Int {
        guard fullPage, contentHeight.isFinite else { return viewport.height }
        return min(max(Int(contentHeight.rounded(.up)), viewport.height), Self.maxPageHeight)
    }
}

public enum WebCaptureError: Error, Equatable, Sendable {
    case emptyURL
    case invalidURL
    case unsupportedScheme(String)
    case timedOut
    case loadFailed(String)
    case snapshotFailed
    case cancelled

    /// One-line, user-facing reason.
    public var reason: String {
        switch self {
        case .emptyURL: "Type a website address, such as example.com."
        case .invalidURL: "That doesn't look like a website address."
        case .unsupportedScheme(let scheme): "Only http and https addresses can be captured (not \(scheme):)."
        case .timedOut: "The page took too long to load."
        case .loadFailed(let detail): "The page couldn't be loaded (\(detail))."
        case .snapshotFailed: "The page loaded, but Sunshot couldn't take its picture."
        case .cancelled: "The capture was cancelled."
        }
    }
}

/// Turns what the user typed into a web address. Only http(s) with a host is accepted; a bare host such as
/// `example.com/page` gets `https://`. `file:`, `data:`, `javascript:` and other schemes are refused.
public enum WebCaptureURL {
    public static func parse(_ text: String) throws(WebCaptureError) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyURL }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { throw .invalidURL }
        let candidate: String
        if let scheme = scheme(of: trimmed) {
            guard ["http", "https"].contains(scheme) else { throw .unsupportedScheme(scheme) }
            candidate = trimmed
        } else {
            candidate = "https://" + trimmed
        }
        guard let components = URLComponents(string: candidate), let host = components.host, !host.isEmpty,
            host.contains(".") || host == "localhost", !host.hasPrefix("."), !host.hasSuffix("."),
            let url = components.url
        else { throw .invalidURL }
        return url
    }

    /// The lower-cased scheme when `text` starts with one (`scheme:`), but not a `host:port` such as
    /// `localhost:8080`.
    static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = text[..<colon]
        let rest = text[text.index(after: colon)...]
        guard let first = scheme.first, first.isLetter,
            scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) })
        else { return nil }
        // "host:8080/…" is a port, not a scheme.
        if !rest.hasPrefix("//"), let digits = rest.split(separator: "/").first, !digits.isEmpty,
            digits.allSatisfy(\.isNumber)
        {
            return nil
        }
        return scheme.lowercased()
    }
}
