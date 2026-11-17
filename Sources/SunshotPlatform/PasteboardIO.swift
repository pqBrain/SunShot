public import AppKit
import SunshotRender
public import UniformTypeIdentifiers

/// Reads images from and writes PNGs to a pasteboard (the general one in the app, a private one in tests).
public enum PasteboardIO {
    /// S16: the unstyled capture Sunshot puts beside a styled copy, so pasting it into the studio doesn't add a
    /// second backdrop around the first. Other apps only see the styled PNG.
    public static let originalCaptureType = NSPasteboard.PasteboardType("app.sunshot.original-capture")

    /// Image bytes on the pasteboard: Sunshot's original capture, then PNG, then TIFF, then the first image file.
    public static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: originalCaptureType) ?? pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff)
        {
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

    /// S16: a styled copy: the styled PNG for every app, plus the original capture for Sunshot's own paste.
    public static func writeStyled(_ styled: Data, original: Data, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(styled, forType: .png)
        item.setData(original, forType: originalCaptureType)
        pasteboard.writeObjects([item])
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
