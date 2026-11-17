import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SunshotRender
import UniformTypeIdentifiers

enum TestImages {
    static func solid(width: Int, height: Int, red: CGFloat = 0.3) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw TestError.setup }
        context.setFillColor(CGColor(srgbRed: red, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw TestError.setup }
        return image
    }

    static func encode(_ image: CGImage, as type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw TestError.setup
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestError.setup }
        return data as Data
    }

    static func png(width: Int = 40, height: Int = 30, red: CGFloat = 0.3) throws -> Data {
        try encode(solid(width: width, height: height, red: red), as: .png)
    }
}

enum TestError: Error { case setup }

/// A fresh temporary directory, removed by `cleanUp()`.
struct TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("sunshot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}

/// A private pasteboard so tests never touch the user's clipboard.
@MainActor
func withPrivatePasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.sunshot.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    try await body(pasteboard)
}

/// Physical memory footprint of this process in bytes.
func memoryFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}
