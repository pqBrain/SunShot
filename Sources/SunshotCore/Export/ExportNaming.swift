public import Foundation

public enum ExportNaming {
    /// Interim S1 file name: `sunshot-yyyy-MM-dd_HH-mm-ss.png` (the configurable template arrives in S4).
    public static func interimFileName(date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let day = "\(c.year ?? 0)-\(two(c.month))-\(two(c.day))"
        return "sunshot-\(day)_\(two(c.hour))-\(two(c.minute))-\(two(c.second)).png"
    }
}

public enum FileExportError: Error, Equatable {
    case writeFailed(reason: String)
}

public enum FileExport {
    /// Writes atomically: either the complete file appears at `url` or nothing does.
    public static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw FileExportError.writeFailed(reason: error.localizedDescription)
        }
    }
}
