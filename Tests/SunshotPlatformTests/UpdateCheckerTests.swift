import Foundation
import SunshotCore
import Testing

@testable import SunshotPlatform

/// The release feed, answered locally: no test ever reaches the network.
private actor FeedStub {
    enum Reply: Sendable {
        case release(String)
        case status(Int)
        case offline
    }

    var reply: Reply
    private(set) var requests: [URLRequest] = []

    init(_ reply: Reply) { self.reply = reply }

    func set(_ reply: Reply) { self.reply = reply }

    func answer(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url ?? ReleaseFeed.latestURL
        switch reply {
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .status(let code):
            return (Data("{}".utf8), Self.response(url, code))
        case .release(let tag):
            let json = """
                {"tag_name": "\(tag)", "name": "", "body": "What's new",
                 "html_url": "https://github.com/pqBrain/SunShot/releases/tag/\(tag)"}
                """
            return (Data(json.utf8), Self.response(url, 200))
        }
    }

    private static func response(_ url: URL, _ code: Int) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)
            ?? URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    }
}

@MainActor
@Suite("Check for updates", .serialized)
struct UpdateCheckerTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    @MainActor
    private struct Fixture {
        let suite = "app.sunshot.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let feed: FeedStub
        let clock = Clock()

        init(_ reply: FeedStub.Reply) {
            defaults = UserDefaults(suiteName: suite) ?? .standard
            feed = FeedStub(reply)
        }

        func checker(version: String = "0.1.0") -> UpdateChecker {
            let feed = feed
            let clock = clock
            return UpdateChecker(
                currentVersion: version, defaults: defaults, fetch: { try await feed.answer($0) },
                now: { clock.now })
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    @Test("[S18-AC3] Check for Updates… answers: available, up to date, nothing published, or couldn't check")
    func userCheck() async throws {
        let fixture = Fixture(.release("v0.2.0"))
        defer { fixture.cleanUp() }
        let checker = fixture.checker()
        var announced: [(UpdateOutcome, Bool)] = []
        checker.onAnnounce = { announced.append(($0, $1)) }
        #expect(checker.state == .idle)

        guard case .available(let release) = await checker.check(userInitiated: true) else {
            Issue.record("expected an update")
            return
        }
        #expect(release.version.description == "0.2.0" && release.title == "Sunshot 0.2.0")
        #expect(checker.state == .finished(.available(release), at: fixture.clock.now))

        await fixture.feed.set(.release("v0.1.0"))
        #expect(await checker.check(userInitiated: true) == .upToDate(latest: try #require(AppVersion("0.1.0"))))
        await fixture.feed.set(.status(404))
        #expect(await checker.check(userInitiated: true) == .noReleases)
        await fixture.feed.set(.status(500))
        #expect(await checker.check(userInitiated: true) == .failed)
        await fixture.feed.set(.offline)
        #expect(await checker.check(userInitiated: true) == .failed)
        #expect(announced.count == 5 && announced.allSatisfy { $0.1 })
        #expect(MenuCatalog.title(.checkForUpdates) == "Check for Updates…")
        #expect(MenuCatalog.shortcut(.checkForUpdates) == nil && MenuCatalog.clashes.isEmpty)
    }

    @Test("[S18-AC3] a malformed feed or a pre-release counts as failed or nothing new")
    func unreadableFeeds() {
        let url = ReleaseFeed.latestURL
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let response = ok ?? URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let page = "\"html_url\": \"https://github.com/pqBrain/SunShot/releases/tag/x\""
        #expect(UpdateChecker.outcome(data: Data("nope".utf8), response: response, current: "0.1.0") == .failed)
        let beta = Data("{\"tag_name\": \"0.2.0-beta\", \(page)}".utf8)
        #expect(UpdateChecker.outcome(data: beta, response: response, current: "0.1.0") == .noReleases)
        let notHTTP = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(UpdateChecker.outcome(data: beta, response: notHTTP, current: "0.1.0") == .failed)
    }

    @Test("[S18-AC4] automatic checks run once a day only while the setting is on; failures are retried and silent")
    func automaticCheck() async throws {
        let fixture = Fixture(.release("v0.1.0"))
        defer { fixture.cleanUp() }
        let checker = fixture.checker()
        var announced = 0
        checker.onAnnounce = { _, _ in announced += 1 }

        #expect(await checker.checkIfDue(enabled: false) == nil)
        #expect(await fixture.feed.requests.isEmpty)
        #expect(await checker.checkIfDue(enabled: true) != nil)
        #expect(checker.lastCheck == fixture.clock.now)
        fixture.clock.now.addTimeInterval(60 * 60)
        #expect(await checker.checkIfDue(enabled: true) == nil)
        #expect(await fixture.feed.requests.count == 1)

        // The last check survives relaunch.
        #expect(fixture.checker().lastCheck == checker.lastCheck)

        let reached = checker.lastCheck
        fixture.clock.now.addTimeInterval(UpdatePolicy.interval)
        await fixture.feed.set(.offline)
        #expect(await checker.checkIfDue(enabled: true) == .failed)
        #expect(checker.lastCheck == reached)
        await fixture.feed.set(.release("v0.3.0"))
        #expect(await checker.checkIfDue(enabled: true) != nil)
        #expect(announced == 1)

        // The setting is saved with the others.
        let store = SettingsStore(defaults: fixture.defaults)
        #expect(store.load().checkForUpdatesAutomatically)
        store.save(AppSettings(checkForUpdatesAutomatically: false))
        #expect(!store.load().checkForUpdatesAutomatically)
    }

    @Test("[S18-AC4] the running app keeps checking on a schedule and stops when asked")
    func schedule() async throws {
        let fixture = Fixture(.release("v0.1.0"))
        defer { fixture.cleanUp() }
        let checker = fixture.checker()
        var enabled = false
        checker.startAutomaticChecks(every: .milliseconds(20)) { enabled }
        try await Task.sleep(for: .milliseconds(80))
        #expect(await fixture.feed.requests.isEmpty)
        enabled = true
        for _ in 0..<100 where checker.lastCheck == nil { try await Task.sleep(for: .milliseconds(20)) }
        checker.stopAutomaticChecks()
        #expect(checker.lastCheck != nil)
        #expect(await fixture.feed.requests.count == 1)
    }

    @Test("[S18-AC5] Skip This Version silences automatic checks for that version only, and is remembered")
    func skipVersion() async throws {
        let fixture = Fixture(.release("v0.2.0"))
        defer { fixture.cleanUp() }
        let checker = fixture.checker()
        var announced: [UpdateOutcome] = []
        checker.onAnnounce = { outcome, _ in announced.append(outcome) }
        checker.skip(try #require(AppVersion("0.2.0")))
        #expect(fixture.checker().skippedVersion?.description == "0.2.0")

        await checker.check(userInitiated: false)
        #expect(announced.isEmpty)
        await checker.check(userInitiated: true)
        #expect(announced.count == 1)
        await fixture.feed.set(.release("v0.2.1"))
        await checker.check(userInitiated: false)
        #expect(announced.count == 2)
    }

    @Test("[S18-AC6] only the version question is sent: a plain GET to the feed with a Sunshot user agent")
    func request() async throws {
        let fixture = Fixture(.release("v0.1.0"))
        defer { fixture.cleanUp() }
        await fixture.checker(version: "0.1.0").check(userInitiated: true)
        let request = try #require(await fixture.feed.requests.first)
        #expect(request.url == ReleaseFeed.latestURL)
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Sunshot/0.1.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(Set((request.allHTTPHeaderFields ?? [:]).keys) == ["User-Agent", "Accept"])
        #expect(UIStrings.aboutPrivacyBody.contains("latest version number"))
        #expect(UIStrings.checkAutomaticallyHint.contains("Nothing about you or your documents is sent"))
    }

    @Test("[S18-AC3] two checks at once share one request")
    func concurrentChecks() async {
        let fixture = Fixture(.release("v0.2.0"))
        defer { fixture.cleanUp() }
        let checker = fixture.checker()
        async let first = checker.check(userInitiated: true)
        async let second = checker.check(userInitiated: false)
        let outcomes = await [first, second]
        #expect(outcomes[0] == outcomes[1])
        #expect(await fixture.feed.requests.count == 1)
    }

    @Test("[S18-AC7] the Updates row says what the last check found and when")
    func statusLine() throws {
        let now = Date()
        let release = ReleaseInfo(
            version: try #require(AppVersion("0.2.0")), title: "Sunshot 0.2.0",
            notes: "Notes", pageURL: ReleaseFeed.releasesPage)
        let latest = release.version
        #expect(UIStrings.updateStatus(.idle, lastCheck: nil) == "Not checked yet")
        #expect(UIStrings.updateStatus(.idle, lastCheck: now, now: now).hasPrefix("Last checked today at "))
        #expect(UIStrings.updateStatus(.checking, lastCheck: nil) == "Checking for updates…")
        #expect(
            UIStrings.updateStatus(.finished(.upToDate(latest: latest), at: now), lastCheck: now, now: now)
                .hasPrefix("Up to date · checked today"))
        #expect(
            UIStrings.updateStatus(.finished(.available(release), at: now), lastCheck: now)
                == "Sunshot 0.2.0 is available")
        #expect(
            UIStrings.updateStatus(.finished(.noReleases, at: now), lastCheck: now, now: now)
                .hasPrefix("No releases yet"))
        let yesterday = now.addingTimeInterval(-2 * UpdatePolicy.interval)
        #expect(
            !UIStrings.updateStatus(.finished(.failed, at: yesterday), lastCheck: nil, now: now)
                .contains("today"))
        #expect(UIStrings.updateAvailableTitle(latest) == "Sunshot 0.2.0 is available")
        #expect(UIStrings.updateAvailableMessage(current: "0.1.0", release: release).hasSuffix("\n\nNotes"))
        var bare = release
        bare.notes = ""
        #expect(UIStrings.updateAvailableMessage(current: "0.1.0", release: bare).hasPrefix("You have 0.1.0."))
        #expect(UIStrings.upToDateMessage(current: "0.1.0") == "Sunshot 0.1.0 is the newest version.")
    }
}
