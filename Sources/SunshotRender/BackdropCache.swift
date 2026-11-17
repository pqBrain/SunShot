import CoreGraphics
import Foundation
import SunshotCore

/// Keeps the last few rendered backdrops (backdrop + below-content effects + preview grid) as raw pixels.
///
/// Most edits (corners, shadow, position, frame, annotations) leave the backdrop unchanged, yet it is the
/// costliest part of a render (per-pixel gradients, wallpapers and effects). A hit copies the stored bytes into
/// the fresh context, so the result is byte-identical to drawing it again.
final class BackdropCache: Sendable {
    static let shared = BackdropCache()

    /// Renders smaller than this (thumbnails) are cheap; caching them would only evict the preview's entry.
    static let minimumPixels = 1_000_000
    static let capacity = 2

    struct Key: Equatable, Sendable {
        let settings: BackdropSettings
        let media: [String: MediaAsset]
        let size: PixelSize
        let grid: TransparencyGrid?
        let pixelWidth: Int
        let pixelHeight: Int
        let bytesPerRow: Int
    }

    private struct Entry: Sendable {
        let key: Key
        let pixels: Data
    }

    private let lock = NSLock()
    // SAFETY: only read or written while holding `lock`.
    nonisolated(unsafe) private var entries: [Entry] = []

    /// Fills `context` with the backdrop, from the cache when the inputs match a stored one.
    func drawBackdrop(
        _ settings: BackdropSettings, size: PixelSize, media: [String: MediaAsset], grid: TransparencyGrid?,
        in context: CGContext
    ) {
        guard context.width * context.height >= Self.minimumPixels, let data = context.data else {
            EffectsRenderer.drawBackdrop(settings, size: size, media: media, grid: grid, in: context)
            return
        }
        let byteCount = context.bytesPerRow * context.height
        // Only the media the backdrop draws matters; other media (slots, video) must not miss the cache.
        let usedID = settings.mediaReference?.id
        let used = media.filter { $0.key == usedID }
        let key = Key(
            settings: settings, media: used, size: size, grid: grid, pixelWidth: context.width,
            pixelHeight: context.height, bytesPerRow: context.bytesPerRow)
        if let pixels = lookup(key), pixels.count == byteCount {
            pixels.withUnsafeBytes { source in
                if let base = source.baseAddress { data.copyMemory(from: base, byteCount: byteCount) }
            }
            return
        }
        EffectsRenderer.drawBackdrop(settings, size: size, media: media, grid: grid, in: context)
        store(Entry(key: key, pixels: Data(bytes: data, count: byteCount)))
    }

    /// Whether an entry for a `width` × `height` pixel render is stored (tests).
    func contains(width: Int, height: Int) -> Bool {
        lock.withLock { entries.contains { $0.key.pixelWidth == width && $0.key.pixelHeight == height } }
    }

    func removeAll() {
        lock.withLock { entries.removeAll() }
    }

    private func lookup(_ key: Key) -> Data? {
        lock.withLock {
            guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.pixels
        }
    }

    private func store(_ entry: Entry) {
        lock.withLock {
            entries.removeAll { $0.key == entry.key }
            entries.insert(entry, at: 0)
            if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        }
    }
}
