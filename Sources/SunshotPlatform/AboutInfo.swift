public import Foundation

/// Settings ▸ About: what this copy of Sunshot is and where it runs, for the About tab and bug reports.
public struct AboutInfo: Equatable, Sendable {
    public var appName: String
    public var version: String
    public var build: String
    public var systemVersion: String
    public var modelIdentifier: String

    public init(appName: String, version: String, build: String, systemVersion: String, modelIdentifier: String) {
        self.appName = appName
        self.version = version
        self.build = build
        self.systemVersion = systemVersion
        self.modelIdentifier = modelIdentifier
    }

    /// The running app: version from the bundle (a development build has none), system from the process.
    public static func current(bundle: Bundle = .main, process: ProcessInfo = .processInfo) -> AboutInfo {
        let info = bundle.infoDictionary ?? [:]
        let os = process.operatingSystemVersion
        let patch = os.patchVersion == 0 ? "" : ".\(os.patchVersion)"
        return AboutInfo(
            appName: Self.bundleValue(info["CFBundleDisplayName"]) ?? "Sunshot",
            version: Self.bundleValue(info["CFBundleShortVersionString"]) ?? "dev",
            build: Self.bundleValue(info["CFBundleVersion"]) ?? "0",
            systemVersion: "\(os.majorVersion).\(os.minorVersion)\(patch)",
            modelIdentifier: Self.hardwareModel() ?? "Mac")
    }

    /// `Version 0.1.0 (42)`.
    public var versionLine: String { "Version \(version) (\(build))" }

    /// `macOS 27.2.1 · Mac16,8`.
    public var systemLine: String { "macOS \(systemVersion) · \(modelIdentifier)" }

    /// Plain text for a bug report: no paths, names or document content.
    public var diagnostics: String {
        [
            "\(appName) \(version) (\(build))",
            "macOS \(systemVersion)",
            "Model \(modelIdentifier)",
            "Locale \(Locale.current.identifier)",
        ].joined(separator: "\n")
    }

    /// Placeholders left in an unbundled Info.plist (`__VERSION__`) count as missing.
    static func bundleValue(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, !text.hasPrefix("__") else { return nil }
        return text
    }

    /// `hw.model`, e.g. `Mac16,8`.
    static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
        let model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return model.isEmpty ? nil : model
    }
}
