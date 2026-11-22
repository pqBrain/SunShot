import Testing

@testable import SunshotPlatform

private final class FakeLoginItem: LoginItemService, @unchecked Sendable {  // SAFETY: tests run it from one task
    var status: LoginItemStatus
    var fails = false
    init(_ status: LoginItemStatus) { self.status = status }
    struct Refused: Error {}
    func register() throws {
        if fails { throw Refused() }
        status = .enabled
    }
    func unregister() throws {
        if fails { throw Refused() }
        status = .disabled
    }
}

@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test("[S19-AC7] turning it on registers the login item and turning it off removes it")
    func toggles() {
        let service = FakeLoginItem(.disabled)
        let login = LaunchAtLogin(service: service)
        #expect(!login.isEnabled)
        #expect(login.setEnabled(true))
        #expect(service.status == .enabled)
        #expect(!login.setEnabled(false))
        #expect(service.status == .disabled)
    }

    @Test("[S19-AC7] a login item the system refuses leaves the toggle off; one awaiting approval shows on")
    func refusedAndPending() {
        let service = FakeLoginItem(.disabled)
        service.fails = true
        #expect(!LaunchAtLogin(service: service).setEnabled(true))
        #expect(LaunchAtLogin(service: FakeLoginItem(.requiresApproval)).isEnabled)
        #expect(!LaunchAtLogin(service: FakeLoginItem(.unavailable)).isEnabled)
    }
}
