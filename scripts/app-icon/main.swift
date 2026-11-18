// S17: writes Sunshot's .iconset from AppIconArtwork (compiled together by scripts/make-app-icon.sh).
// Usage: make-app-icon <iconset-dir>   (or: make-app-icon --preview <pixels> <file.png>)
import Foundation

let arguments = CommandLine.arguments
func write(_ pixels: Int, to url: URL) {
    guard let data = AppIconArtwork.pngData(pixels: pixels) else {
        FileHandle.standardError.write(Data("cannot render \(pixels) px\n".utf8))
        exit(1)
    }
    do { try data.write(to: url) } catch {
        FileHandle.standardError.write(Data("cannot write \(url.path): \(error)\n".utf8))
        exit(1)
    }
}

if arguments.count == 4, arguments[1] == "--preview", let pixels = Int(arguments[2]) {
    write(pixels, to: URL(fileURLWithPath: arguments[3]))
} else if arguments.count == 2 {
    let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for entry in AppIconArtwork.iconsetEntries {
        write(entry.pixels, to: folder.appendingPathComponent(entry.name))
    }
} else {
    FileHandle.standardError.write(Data("usage: make-app-icon <iconset-dir> | --preview <pixels> <file.png>\n".utf8))
    exit(2)
}
