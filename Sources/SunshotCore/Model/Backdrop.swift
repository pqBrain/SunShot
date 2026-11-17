/// The four backdrop types offered by the inspector.
public enum BackdropKind: String, Codable, CaseIterable, Sendable {
    case none, solid, gradient, image
}

/// A user image stored in the document (bytes live in the document's media, keyed by `id`).
public struct MediaReference: Codable, Hashable, Sendable {
    public let id: String
    public let fileName: String?
    public let pixelSize: PixelSize

    public init(id: String, fileName: String?, pixelSize: PixelSize) {
        self.id = id
        self.fileName = fileName
        self.pixelSize = pixelSize
    }
}

public enum BackdropImage: Codable, Hashable, Sendable {
    /// One of Sunshot's generated wallpapers (the recipe travels with the document).
    case wallpaper(Wallpaper)
    /// A user file, drawn with aspect-preserving "fill" (cover) scaling, centred.
    case file(MediaReference)
}

/// What is drawn behind the content.
public enum Backdrop: Codable, Hashable, Sendable {
    /// Transparent (a checkerboard is shown in the preview only).
    case none
    case solid(RGBAColor)
    case gradient(GradientSpec)
    case image(BackdropImage)

    public var kind: BackdropKind {
        switch self {
        case .none: .none
        case .solid: .solid
        case .gradient: .gradient
        case .image: .image
        }
    }

    /// Whether every backdrop pixel is fully opaque (user images may carry alpha, so they count as not opaque).
    public var isOpaque: Bool {
        switch self {
        case .none: false
        case .solid(let color): color.alpha >= 1
        case .gradient(let spec): spec.isOpaque
        case .image(.wallpaper): true
        case .image(.file): false
        }
    }
}

/// The active backdrop type plus the last-used value of every type, so switching Solid → Gradient → Solid brings
/// the previous colour back. Part of the document, so undo restores it too.
public struct BackdropSettings: Codable, Hashable, Sendable {
    public var kind: BackdropKind
    public var solidColor: RGBAColor
    public var gradient: GradientSpec
    public var image: BackdropImage
    /// S8: blur / noise / saturation / opacity, pattern, vignette and overlay (all off by default).
    public var effects: BackdropEffects
    /// S8: the current Auto-background arrangement (changed by Shuffle).
    public var autoShuffle: UInt64

    public init(
        kind: BackdropKind = .solid, solidColor: RGBAColor = SunshotDefaults.backdropColor,
        gradient: GradientSpec = SunshotDefaults.gradient, image: BackdropImage = .wallpaper(SunshotDefaults.wallpaper),
        effects: BackdropEffects = BackdropEffects(), autoShuffle: UInt64 = 0
    ) {
        self.kind = kind
        self.solidColor = solidColor
        self.gradient = gradient
        self.image = image
        self.effects = effects
        self.autoShuffle = autoShuffle
    }

    /// The backdrop being drawn. Setting it selects that type and remembers its value.
    public var backdrop: Backdrop {
        get {
            switch kind {
            case .none: .none
            case .solid: .solid(solidColor)
            case .gradient: .gradient(gradient)
            case .image: .image(image)
            }
        }
        set {
            kind = newValue.kind
            switch newValue {
            case .none: break
            case .solid(let color): solidColor = color
            case .gradient(let spec): gradient = spec
            case .image(let image): self.image = image
            }
        }
    }

    /// The user image referenced by the settings (current or remembered), if any.
    public var mediaReference: MediaReference? {
        if case .file(let reference) = image { return reference }
        return nil
    }
}

extension BackdropSettings {
    private enum CodingKeys: String, CodingKey {
        case kind, solidColor, gradient, image, effects, autoShuffle
    }

    /// Documents saved before S8 have no `effects` / `autoShuffle`: they decode with the defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(BackdropKind.self, forKey: .kind),
            solidColor: try container.decode(RGBAColor.self, forKey: .solidColor),
            gradient: try container.decode(GradientSpec.self, forKey: .gradient),
            image: try container.decode(BackdropImage.self, forKey: .image),
            effects: try container.decodeIfPresent(BackdropEffects.self, forKey: .effects) ?? BackdropEffects(),
            autoShuffle: try container.decodeIfPresent(UInt64.self, forKey: .autoShuffle) ?? 0)
    }
}
