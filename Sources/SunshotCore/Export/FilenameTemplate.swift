public import Foundation

/// Values substituted into a file-name template.
public struct FilenameContext: Hashable, Sendable {
    public var templateName: String
    public var scale: ExportScale
    public var date: Date
    public var width: Int
    public var height: Int
    public var format: ExportFormat

    public init(
        templateName: String = SunshotDefaults.templateName, scale: ExportScale, date: Date, width: Int, height: Int,
        format: ExportFormat
    ) {
        self.templateName = templateName
        self.scale = scale
        self.date = date
        self.width = width
        self.height = height
        self.format = format
    }
}

/// Export file names from a template such as `{TEMPLATE}_{SCALE}_sunshot_{DATE}`.
///
/// Tokens: `{DATE}` (`yyyy-MM-dd_HH-mm-ss`, local time), `{TEMPLATE}`, `{SCALE}` (`1x 2x 4k 6k`), `{RANDOM}`
/// (6 lowercase letters/digits), `{WIDTH}`, `{HEIGHT}` (output pixels). Unknown tokens stay as written.
public enum FilenameTemplate {
    public static let tokens = ["DATE", "TEMPLATE", "SCALE", "RANDOM", "WIDTH", "HEIGHT"]
    /// Longest base name (before the extension), so the full name stays within the 255-byte filesystem limit.
    public static let maxBaseLength = 200
    static let randomAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// Builds `<base>.<ext>`. An empty template falls back to the default; `/ : \` become `-`.
    public static func fileName(
        template: String, context: FilenameContext, timeZone: TimeZone = .current,
        random: () -> String = { FilenameTemplate.randomToken() }
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? SunshotDefaults.filenameTemplate : trimmed
        var base = expand(source, context: context, timeZone: timeZone, random: random)
        base = String(base.map { "/:\\".contains($0) ? "-" : $0 })
        let limit = maxBaseLength
        while base.count > limit || base.utf8.count > limit { base.removeLast() }
        if base.trimmingCharacters(in: .whitespaces).isEmpty { base = context.templateName }
        return "\(base).\(context.format.fileExtension)"
    }

    /// `{NAME}` tokens in `template` that aren't known (left as literal text when expanding).
    public static func unknownTokens(in template: String) -> [String] {
        placeholders(in: template).filter { !tokens.contains($0) }
    }

    /// 6 lowercase letters or digits from `generator`.
    public static func randomToken<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<6).map { _ in randomAlphabet[Int.random(in: 0..<randomAlphabet.count, using: &generator)] })
    }

    public static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return randomToken(using: &generator)
    }

    /// `2026-11-17_08-19-05`.
    public static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(c.year ?? 0)-\(two(c.month))-\(two(c.day))_\(two(c.hour))-\(two(c.minute))-\(two(c.second))"
    }

    private static func expand(
        _ template: String, context: FilenameContext, timeZone: TimeZone, random: () -> String
    ) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else { break }
            let name = String(rest[afterOpen..<close])
            result += value(of: name, context: context, timeZone: timeZone, random: random) ?? "{\(name)}"
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    private static func value(
        of token: String, context: FilenameContext, timeZone: TimeZone, random: () -> String
    ) -> String? {
        switch token {
        case "DATE": dateString(context.date, timeZone: timeZone)
        case "TEMPLATE": context.templateName
        case "SCALE": context.scale.token
        case "RANDOM": random()
        case "WIDTH": String(context.width)
        case "HEIGHT": String(context.height)
        default: nil
        }
    }

    private static func placeholders(in template: String) -> [String] {
        var names: [String] = []
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else { break }
            names.append(String(rest[afterOpen..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }
}
