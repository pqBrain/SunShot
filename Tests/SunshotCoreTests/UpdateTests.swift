import Foundation
import Testing

@testable import SunshotCore

@Suite("Update check model")
struct UpdateTests {
    private func version(_ text: String) throws -> AppVersion {
        try #require(AppVersion(text))
    }

    private func release(_ text: String) throws -> ReleaseInfo {
        ReleaseInfo(
            version: try version(text), title: "Sunshot \(text)",
            pageURL: try #require(URL(string: "https://github.com/pqBrain/SunShot/releases/tag/v\(text)")))
    }

    // MARK: Versions

    @Test("[S18-AC1] versions parse with or without v, ignore build metadata and reject non-versions")
    func parsing() throws {
        #expect(try version("0.1.0").numbers == [0, 1, 0])
        #expect(try version("v1.2").description == "1.2")
        #expect(try version(" V2.0.1+42 ").description == "2.0.1")
        #expect(try version("1.0.0-beta.2").preRelease == ["beta", "2"])
        #expect(try version("1.0.0-beta.2").isPreRelease)
        for bad in ["", "dev", "__VERSION__", "1..2", "1.x", "1.0-", "1.0-beta..1", "v"] {
            #expect(AppVersion(bad) == nil, "\(bad)")
        }
    }

    @Test("[S18-AC1] versions order numerically; missing parts are 0; a pre-release comes before its release")
    func ordering() throws {
        #expect(try version("0.1.0") < version("0.2.0"))
        #expect(try version("0.9.0") < version("0.10.0"))
        #expect(try version("1.9") < version("1.10.1"))
        #expect(try version("0.1") == version("0.1.0"))
        #expect(try Set([version("0.1"), version("0.1.0")]).count == 1)
        #expect(try version("1.0.0-beta") < version("1.0.0"))
        #expect(try version("1.0.0-alpha") < version("1.0.0-alpha.1"))
        #expect(try version("1.0.0-alpha.1") < version("1.0.0-alpha.beta"))
        #expect(try version("1.0.0-beta.2") < version("1.0.0-beta.11"))
        #expect(try version("1.0.0-beta.11") < version("1.0.0-rc.1"))
        #expect(try version("1.0.0-rc.1") == version("1.0.0-rc.1"))
        #expect(try !(version("2.0.0") < version("1.9.9")))
    }

    @Test("[S18-AC8] this build is release 0.1.0")
    func releaseVersion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        let current = try version(text)
        #expect(current == (try version("0.1.0")) && !current.isPreRelease)
        #expect(current.description == text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Feed

    @Test("[S18-AC2] the latest release is read from the feed: version, title, notes, page and app archive")
    func parseRelease() throws {
        let json = """
            {"tag_name": "v0.2.0", "name": "Sunshot 0.2", "body": "  Faster export.\\n  ",
             "html_url": "https://github.com/pqBrain/SunShot/releases/tag/v0.2.0", "draft": false,
             "prerelease": false, "published_at": "2026-12-01T09:30:00Z",
             "assets": [{"name": "checksums.txt", "browser_download_url": "https://example.com/sums"},
                        {"name": "Sunshot-0.2.0.zip", "browser_download_url": "https://example.com/Sunshot.zip"}]}
            """
        let release = try ReleaseFeed.parse(Data(json.utf8))
        #expect(release.version == (try version("0.2.0")))
        #expect(release.title == "Sunshot 0.2" && release.notes == "Faster export.")
        #expect(release.pageURL.absoluteString == "https://github.com/pqBrain/SunShot/releases/tag/v0.2.0")
        #expect(release.downloadURL?.absoluteString == "https://example.com/Sunshot.zip")
        #expect(release.publishedAt == Date(timeIntervalSince1970: 1_796_117_400))
        #expect(ReleaseFeed.latestURL.absoluteString == "https://api.github.com/repos/pqBrain/SunShot/releases/latest")
        #expect(ReleaseFeed.releasesPage.absoluteString == "https://github.com/pqBrain/SunShot/releases")
    }

    @Test("[S18-AC2] an untitled release is named after its version; drafts, pre-releases and junk are refused")
    func parseEdgeCases() throws {
        let page = "\"html_url\": \"https://github.com/pqBrain/SunShot/releases/tag/v1\""
        let untitled = try ReleaseFeed.parse(Data("{\"tag_name\": \"1.0\", \"name\": \" \", \(page)}".utf8))
        #expect(untitled.title == "Sunshot 1.0" && untitled.notes.isEmpty && untitled.downloadURL == nil)
        #expect(throws: ReleaseFeed.ParseError.notARelease) {
            try ReleaseFeed.parse(Data("{\"tag_name\": \"1.1\", \"draft\": true, \(page)}".utf8))
        }
        #expect(throws: ReleaseFeed.ParseError.notARelease) {
            try ReleaseFeed.parse(Data("{\"tag_name\": \"1.1\", \"prerelease\": true, \(page)}".utf8))
        }
        #expect(throws: ReleaseFeed.ParseError.notARelease) {
            try ReleaseFeed.parse(Data("{\"tag_name\": \"1.1.0-rc.1\", \(page)}".utf8))
        }
        #expect(throws: ReleaseFeed.ParseError.unreadableVersion("nightly")) {
            try ReleaseFeed.parse(Data("{\"tag_name\": \"nightly\", \(page)}".utf8))
        }
        #expect(throws: ReleaseFeed.ParseError.malformed) { try ReleaseFeed.parse(Data("{\"message\": 1}".utf8)) }
    }

    @Test("[S18-AC2] long release notes are cut at a line break for the alert")
    func notesExcerpt() throws {
        var info = try release("1.0.0")
        info.notes = "short"
        #expect(info.notesExcerpt() == "short")
        info.notes = "line one\nline two\nline three"
        #expect(info.notesExcerpt(limit: 15) == "line one\n…")
        info.notes = String(repeating: "x", count: 20)
        #expect(info.notesExcerpt(limit: 10) == String(repeating: "x", count: 10) + "\n…")
    }

    // MARK: Policy

    @Test("[S18-AC3] a newer release is available; the same, an older one or a development build is up to date")
    func outcome() throws {
        let latest = try release("0.2.0")
        #expect(UpdatePolicy.outcome(current: "0.1.0", latest: latest) == .available(latest))
        #expect(UpdatePolicy.outcome(current: "0.1.9-beta", latest: latest) == .available(latest))
        #expect(UpdatePolicy.outcome(current: "0.2.0", latest: latest) == .upToDate(latest: latest.version))
        #expect(UpdatePolicy.outcome(current: "0.3.0", latest: latest) == .upToDate(latest: latest.version))
        #expect(UpdatePolicy.outcome(current: "dev", latest: latest) == .upToDate(latest: latest.version))
    }

    @Test("[S18-AC4] an automatic check is due once a day (or when the clock went backwards)")
    func due() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdatePolicy.isDue(lastCheck: nil, now: now))
        #expect(!UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(!UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-UpdatePolicy.interval + 1), now: now))
        #expect(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-UpdatePolicy.interval), now: now))
        #expect(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test(
        "[S18-AC3] [S18-AC5] a check the user asked for always answers; an automatic one only for an unskipped update")
    func announce() throws {
        let latest = try release("0.2.0")
        let skipped = try version("0.2.0")
        for outcome: UpdateOutcome in [.upToDate(latest: latest.version), .noReleases, .failed, .available(latest)] {
            #expect(UpdatePolicy.shouldAnnounce(outcome, userInitiated: true, skipped: skipped))
        }
        #expect(UpdatePolicy.shouldAnnounce(.available(latest), userInitiated: false, skipped: nil))
        #expect(!UpdatePolicy.shouldAnnounce(.available(latest), userInitiated: false, skipped: skipped))
        #expect(UpdatePolicy.shouldAnnounce(.available(latest), userInitiated: false, skipped: try version("0.1.5")))
        for quiet: UpdateOutcome in [.upToDate(latest: latest.version), .noReleases, .failed] {
            #expect(!UpdatePolicy.shouldAnnounce(quiet, userInitiated: false, skipped: nil))
        }
    }

    @Test("[S18-AC4] automatic checks are on by default")
    func defaultSetting() {
        #expect(AppSettings().checkForUpdatesAutomatically)
        #expect(!AppSettings(checkForUpdatesAutomatically: false).checkForUpdatesAutomatically)
    }
}
