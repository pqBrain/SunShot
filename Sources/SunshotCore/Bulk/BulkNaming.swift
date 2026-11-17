public import Foundation

/// Batch export file names: the S4 template plus `{INDEX}` and `{NAME}`, made unique.
public enum BulkNaming {
    public static let indexToken = "{INDEX}"
    public static let nameToken = "{NAME}"

    /// 1-based position `index + 1`, zero-padded to the digit count of `count` (`01` … `12`).
    public static func indexString(_ index: Int, count: Int) -> String {
        let width = String(max(count, 1)).count
        let digits = String(index + 1)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    /// The per-item template: `{INDEX}` and `{NAME}` substituted, `_{INDEX}` appended when the template has no
    /// `{INDEX}` so a batch never produces the same name twice by design. An empty template uses the default.
    public static func itemTemplate(_ template: String, index: Int, count: Int, sourceName: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? SunshotDefaults.filenameTemplate : trimmed
        if !result.contains(indexToken) { result += "_" + indexToken }
        // Braces in the source name must not be read as tokens later.
        let safeName = String(sourceName.filter { $0 != "{" && $0 != "}" })
        result = result.replacingOccurrences(of: indexToken, with: indexString(index, count: count))
        return result.replacingOccurrences(of: nameToken, with: safeName)
    }

    /// `<base>.<ext>` for item `index` of `count`, before uniqueness is applied.
    public static func fileName(
        template: String, index: Int, count: Int, sourceName: String, context: FilenameContext,
        timeZone: TimeZone = .current, random: () -> String = { FilenameTemplate.randomToken() }
    ) -> String {
        FilenameTemplate.fileName(
            template: itemTemplate(template, index: index, count: count, sourceName: sourceName), context: context,
            timeZone: timeZone, random: random)
    }
}

/// Hands out file names that are unique within a batch and don't exist in the folder yet (never overwrite).
public struct BulkNameAllocator: Sendable {
    /// Lower-cased: the default macOS file system is case-insensitive.
    private var used: Set<String> = []

    public init() {}

    /// `name`, or `name-2.ext`, `name-3.ext`, … — the first that wasn't handed out and for which `exists` is false.
    public mutating func claim(_ name: String, exists: (String) -> Bool) -> String {
        let (stem, ext) = Self.split(name)
        var candidate = name
        var counter = 1
        while used.contains(candidate.lowercased()) || exists(candidate) {
            counter += 1
            candidate = "\(stem)-\(counter)" + (ext.isEmpty ? "" : ".\(ext)")
        }
        used.insert(candidate.lowercased())
        return candidate
    }

    static func split(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }
}
