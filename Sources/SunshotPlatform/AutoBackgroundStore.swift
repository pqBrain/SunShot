public import CoreGraphics
import Foundation
public import SunshotCore
public import SunshotRender

/// S8: the content palette and the five auto-background suggestions with thumbnails, cached per content image and
/// shuffle value so the inspector does not re-extract on every redraw.
@MainActor
public final class AutoBackgroundStore {
    public static let shared = AutoBackgroundStore()

    public struct Suggestion: Identifiable, Sendable {
        public let wallpaper: Wallpaper
        public let thumbnail: CGImage?
        public var id: String { wallpaper.id }
    }

    public struct State: Sendable {
        public let palette: [RGBAColor]
        public let suggestions: [Suggestion]
        public static let empty = State(palette: [], suggestions: [])
    }

    private var key: (content: UUID, shuffle: UInt64)?
    private var cached = State.empty
    private var palette: (content: UUID, colors: [RGBAColor])?

    public init() {}

    public func state(for session: EditorSession) -> State {
        guard let content = session.document.content else { return .empty }
        let shuffle = session.backdropSettings.autoShuffle
        if let key, key.content == content.id, key.shuffle == shuffle { return cached }
        let colors: [RGBAColor]
        if let palette, palette.content == content.id {
            colors = palette.colors
        } else {
            colors = session.autoPalette
            palette = (content.id, colors)
        }
        let suggestions = AutoBackground.suggestions(palette: colors, shuffle: shuffle).map { wallpaper in
            Suggestion(
                wallpaper: wallpaper,
                thumbnail: try? Renderer.renderBackdrop(
                    .image(.wallpaper(wallpaper)), size: BackdropLibrary.thumbnailSize))
        }
        key = (content.id, shuffle)
        cached = State(palette: colors, suggestions: suggestions)
        return cached
    }
}
