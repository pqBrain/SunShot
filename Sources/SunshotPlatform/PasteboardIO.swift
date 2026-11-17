public import AppKit
import SunshotRender
public import UniformTypeIdentifiers

/// Reads images from and writes PNGs to a pasteboard (the general one in the app, a private one in tests).
public enum PasteboardIO {
    /// Image bytes on the pasteboard: PNG, then TIFF, then the first image file URL.
    public static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return data
        }
        guard let url = imageFileURL(on: pasteboard) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.png, .tiff]) != nil || imageFileURL(on: pasteboard) != nil
    }

    /// Replaces the pasteboard contents with exactly one PNG representation.
    public static func writePNG(_ data: Data, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    private static func imageFileURL(on pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first(where: isSupportedImageFile)
    }
}

/// Whether a file's extension is one Sunshot can import.
public func isSupportedImageFile(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return ImageLoader.supportedTypes.contains { type.conforms(to: $0) }
}

public enum ImageTypes {
    /// Types offered in the open panel.
    public static var supported: [UTType] { ImageLoader.supportedTypes }
}
