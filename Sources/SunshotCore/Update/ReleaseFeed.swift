public import Foundation

/// S18: one published Sunshot release, as the release feed (GitHub's "latest release" API) describes it.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: AppVersion
    /// The release's title, or `Sunshot <version>` when it has none.
    public var title: String
    /// Release notes (Markdown as written), trimmed; may be empty.
    public var notes: String
    /// The release page, where the user downloads it.
    public var pageURL: URL
    /// A downloadable app archive (`.zip` or `.dmg`) attached to the release, if any.
    public var downloadURL: URL?
    public var publishedAt: Date?

    public init(
        version: AppVersion, title: String, notes: String = "", pageURL: URL, downloadURL: URL? = nil,
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
    }

    /// Notes cut to `limit` characters at a line break where possible, for an alert.
    public func notesExcerpt(limit: Int = 600) -> String {
        guard notes.count > limit else { return notes }
        let cut = notes.prefix(limit)
        let end = cut.lastIndex(of: "\n") ?? cut.endIndex
        return String(cut[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n…"
    }
}

/// S18: where Sunshot looks for new releases, and how it reads the answer.
public enum ReleaseFeed {
    /// The repository Sunshot is published from.
    public static let repository = "pqBrain/SunShot"
    /// Latest published release: drafts and pre-releases are never returned by this endpoint.
    public static let latestURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(repository)/releases/latest"
        return components.url ?? URL(fileURLWithPath: "/")
    }()
    /// Where "Download" goes when the feed can't be read.
    public static let releasesPage: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/releases"
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    public enum ParseError: Error, Equatable {
        case malformed
        case unreadableVersion(String)
        /// A draft or pre-release: never offered as an update.
        case notARelease
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let draft: Bool?
        let prerelease: Bool?
        let publishedAt: Date?
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, draft, prerelease, assets
            case htmlURL = "html_url"
            case publishedAt = "published_at"
        }
    }

    /// Reads a GitHub release object.
    public static func parse(_ data: Data) throws(ParseError) -> ReleaseInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: data)
        } catch {
            throw .malformed
        }
        if payload.draft == true || payload.prerelease == true { throw .notARelease }
        guard let version = AppVersion(payload.tagName) else { throw .unreadableVersion(payload.tagName) }
        if version.isPreRelease { throw .notARelease }
        let title = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let archive = payload.assets?.first { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".dmg") || name.hasSuffix(".zip")
        }
        return ReleaseInfo(
            version: version,
            title: title.isEmpty ? "Sunshot \(version)" : title,
            notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            pageURL: payload.htmlURL,
            downloadURL: archive?.browserDownloadURL,
            publishedAt: payload.publishedAt)
    }
}
