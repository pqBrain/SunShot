/// Text ↔ set of 1-based line numbers for the "Highlighted lines" field: `2, 4-6` ↔ {2, 4, 5, 6}.
public enum HighlightedLines {
    /// Largest range one entry may span (keeps a typo like `1-99999999` from building a huge set).
    public static let maxRangeLength = 10_000

    /// Parses comma- or space-separated line numbers and ranges (`-` or `–`). Empty text is the empty set;
    /// anything invalid (not a number, 0, a reversed or oversized range) returns nil.
    public static func parse(_ text: String) -> Set<Int>? {
        var lines: Set<Int> = []
        let parts = text.split { $0 == "," || $0 == " " || $0 == ";" }
        for part in parts {
            let bounds = part.split(omittingEmptySubsequences: false) { $0 == "-" || $0 == "–" }
            switch bounds.count {
            case 1:
                guard let line = Int(bounds[0]), line >= 1 else { return nil }
                lines.insert(line)
            case 2:
                guard let low = Int(bounds[0]), let high = Int(bounds[1]), low >= 1, low <= high,
                    high - low < maxRangeLength
                else { return nil }
                lines.formUnion(low...high)
            default:
                return nil
            }
        }
        return lines
    }

    /// `2, 4–6`: sorted, consecutive runs of two or more collapsed into a range with an en dash.
    public static func format(_ lines: Set<Int>) -> String {
        var parts: [String] = []
        var sorted = lines.sorted()[...]
        while let first = sorted.popFirst() {
            var last = first
            while let next = sorted.first, next == last + 1 {
                last = next
                sorted.removeFirst()
            }
            parts.append(first == last ? "\(first)" : "\(first)–\(last)")
        }
        return parts.joined(separator: ", ")
    }
}
