import Foundation

/// S18: a release version such as `0.1.0`, `v1.2` or `1.0.0-beta.2`, ordered the semantic-versioning way: numbers
/// compare numerically (missing parts count as 0) and a pre-release comes before its release.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// `[major, minor, patch, …]`, at least one part.
    public let numbers: [Int]
    /// The part after `-` (`beta.2`), empty for a release.
    public let preRelease: [String]

    /// Nil for anything that does not start with a number (`dev`, an empty bundle value, `__VERSION__`).
    public init?(_ text: String) {
        var core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.first == "v" || core.first == "V" { core.removeFirst() }
        // Build metadata (`+42`) never affects ordering.
        if let plus = core.firstIndex(of: "+") { core = String(core[..<plus]) }
        var pre: [String] = []
        if let dash = core.firstIndex(of: "-") {
            pre = core[core.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            core = String(core[..<dash])
            if pre.isEmpty || pre.contains(where: \.isEmpty) { return nil }
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        self.numbers = numbers
        self.preRelease = pre
    }

    public var isPreRelease: Bool { !preRelease.isEmpty }

    /// `0.1.0`, `1.0.0-beta.2`.
    public var description: String {
        let core = numbers.map(String.init).joined(separator: ".")
        return preRelease.isEmpty ? core : core + "-" + preRelease.joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == .orderedSame
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
        hasher.combine(preRelease)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> ComparisonResult {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        switch (lhs.preRelease.isEmpty, rhs.preRelease.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): return comparePreRelease(lhs.preRelease, rhs.preRelease)
        }
    }

    /// Identifier by identifier: numeric ones numerically and below alphanumeric ones; more identifiers win a tie.
    private static func comparePreRelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case (let l?, let r?): return l < r ? .orderedAscending : .orderedDescending
            case (.some, nil): return .orderedAscending
            case (nil, .some): return .orderedDescending
            case (nil, nil): return left < right ? .orderedAscending : .orderedDescending
            }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }
}
