public import Foundation

/// Turns chosen or dropped URLs (files and folders) into batch items.
public enum BulkImportCollector {
    public struct Result: Hashable, Sendable {
        public var items: [BulkItem]
        /// Files that aren't supported images (and folders that couldn't be read).
        public var skipped: Int

        public init(items: [BulkItem] = [], skipped: Int = 0) {
            self.items = items
            self.skipped = skipped
        }
    }

    /// Files are kept in the given order; a folder contributes its top-level, non-hidden files in Finder name
    /// order (numeric-aware). Subfolders are ignored (not recursive). `isSupported` decides by file type.
    public static func collect(
        _ urls: [URL], isSupported: (URL) -> Bool, fileManager: FileManager = .default
    ) -> Result {
        var result = Result()
        for url in urls {
            if isDirectory(url, fileManager: fileManager) {
                guard
                    let children = try? fileManager.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                else {
                    result.skipped += 1
                    continue
                }
                let files =
                    children
                    .filter { !isDirectory($0, fileManager: fileManager) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                for file in files { append(file, access: url, isSupported: isSupported, to: &result) }
            } else {
                append(url, access: url, isSupported: isSupported, to: &result)
            }
        }
        return result
    }

    /// Whether any URL is a folder (folders always go to a batch, even alone).
    public static func containsDirectory(_ urls: [URL], fileManager: FileManager = .default) -> Bool {
        urls.contains { isDirectory($0, fileManager: fileManager) }
    }

    static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func append(_ url: URL, access: URL, isSupported: (URL) -> Bool, to result: inout Result) {
        if isSupported(url) {
            result.items.append(BulkItem(url: url, accessURL: access))
        } else {
            result.skipped += 1
        }
    }
}
