import Foundation
import ServiceManagement
import os

/// What the login-item service reports for this app.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled, disabled
    /// Registered, but the user has to approve it in System Settings ▸ General ▸ Login Items.
    case requiresApproval
    /// Not available (e.g. running outside an app bundle).
    case unavailable
}

/// The slice of `SMAppService` Sunshot uses, so tests can stand in for the system.
public protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// The real service: this app as a login item.
public struct SystemLoginItemService: LoginItemService {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// S19: Settings ▸ Open Sunshot at login. The system, not UserDefaults, is the source of truth: the user can also
/// remove the login item in System Settings, and the toggle must then show off.
public struct LaunchAtLogin {
    private static let log = Logger(subsystem: "app.sunshot", category: "launch-at-login")
    private let service: any LoginItemService

    public init(service: any LoginItemService = SystemLoginItemService()) {
        self.service = service
    }

    public var status: LoginItemStatus { service.status }

    /// Whether Sunshot will open at login (a pending approval counts: the user already asked for it).
    public var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// Turns the login item on or off. Returns the state afterwards, which differs from `enabled` when the
    /// system refused.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled != isEnabled else { return isEnabled }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            Self.log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}
