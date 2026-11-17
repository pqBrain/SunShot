/// Space the frame adds around the content on each side, in content pixels at 1×.
public struct FrameInsets: Hashable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = FrameInsets()
    public var horizontal: Double { left + right }
    public var vertical: Double { top + bottom }
}

/// A card drawn behind a stack frame.
public struct BackCard: Hashable, Sendable {
    public let rect: LayoutRect
    public let opacity: Double
}

/// Where each part of a frame goes, relative to the frame box (content + chrome), in unscaled content pixels.
///
/// The box is what the canvas lays out instead of the bare content, so chrome grows an Auto canvas and never
/// covers the content. With frame `none` the box, the window and the content are the same rectangle.
public struct FrameGeometry: Hashable, Sendable {
    public let kind: FrameKind
    /// UI scale factor (1 = 100 %).
    public let scale: Double
    /// The rounded, shadowed silhouette: the window (bar + content), or the front card.
    public let window: LayoutRect
    public let content: LayoutRect
    /// Title bar or toolbar of window frames.
    public let bar: LayoutRect?
    /// Cards behind the front card (stack frames), farthest first.
    public let backCards: [BackCard]
    /// Card and thick-border frames are concentric: their outer radius is the S2 radius plus this.
    public let outerRadiusExtra: Double

    /// Chrome around the content for `frame`.
    public static func insets(for frame: Frame) -> FrameInsets {
        let scale = frame.scaleFactor
        switch frame.kind {
        case .none:
            return .zero
        case .macWindow:
            return FrameInsets(top: FrameMetrics.macBarHeight * scale)
        case .browserWindow:
            return FrameInsets(top: FrameMetrics.browserBarHeight * scale)
        case .winWindow:
            return FrameInsets(top: FrameMetrics.winBarHeight * scale)
        case .card, .stack, .stack2:
            let pad = FrameMetrics.cardPadding * scale
            let behind = Double(backCardCount(frame.kind)) * FrameMetrics.stackOffset * scale
            return FrameInsets(top: pad + behind, left: pad, bottom: pad, right: pad)
        case .thickBorder:
            let width = FrameMetrics.thickBorderWidth * scale
            return FrameInsets(top: width, left: width, bottom: width, right: width)
        }
    }

    static func backCardCount(_ kind: FrameKind) -> Int {
        switch kind {
        case .stack: 1
        case .stack2: 2
        default: 0
        }
    }

    /// Geometry for a frame box of `boxWidth` × `boxHeight` (content size + `insets(for:)`).
    public init(frame: Frame, boxWidth: Double, boxHeight: Double) {
        let scale = frame.scaleFactor
        let insets = Self.insets(for: frame)
        kind = frame.kind
        self.scale = scale
        content = LayoutRect(
            x: insets.left, y: insets.top, width: max(0, boxWidth - insets.horizontal),
            height: max(0, boxHeight - insets.vertical))

        let behind = Double(Self.backCardCount(frame.kind)) * FrameMetrics.stackOffset * scale
        let front = LayoutRect(x: 0, y: behind, width: boxWidth, height: max(0, boxHeight - behind))
        window = front
        bar = frame.kind.hasTitle ? LayoutRect(x: 0, y: 0, width: boxWidth, height: insets.top) : nil

        var cards: [BackCard] = []
        for index in (0..<Self.backCardCount(frame.kind)).reversed() {
            let factor = FrameMetrics.stackScales[index]
            let width = front.width * factor
            let height = front.height * factor
            let lift = Double(index + 1) * FrameMetrics.stackOffset * scale
            // The offset is where the card's top edge peeks out above the front card.
            let rect = LayoutRect(x: front.midX - width / 2, y: front.y - lift, width: width, height: height)
            cards.append(BackCard(rect: rect, opacity: FrameMetrics.stackOpacities[index]))
        }
        backCards = cards

        switch frame.kind {
        case .card, .stack, .stack2: outerRadiusExtra = FrameMetrics.cardPadding * scale
        case .thickBorder: outerRadiusExtra = FrameMetrics.thickBorderWidth * scale
        default: outerRadiusExtra = 0
        }
    }

    /// Area of the bar the title may use (mac: centred between the traffic lights and a mirrored margin;
    /// Windows: left-aligned up to the caption buttons; browser: inside the address field).
    public var titleRect: LayoutRect? {
        guard let bar else { return nil }
        switch kind {
        case .macWindow:
            let side = trafficLightsWidth + 2 * FrameMetrics.trafficLightInset * scale
            return LayoutRect(x: side, y: bar.y, width: max(0, bar.width - 2 * side), height: bar.height)
        case .winWindow:
            let left = 12 * scale
            return LayoutRect(
                x: left, y: bar.y, width: max(0, bar.width - left - 3 * winButtonWidth - 8 * scale),
                height: bar.height)
        case .browserWindow:
            guard let field = addressField else { return nil }
            let inset = 26 * scale
            return LayoutRect(
                x: field.x + inset, y: field.y, width: max(0, field.width - 2 * inset), height: field.height)
        default:
            return nil
        }
    }

    /// Total width of the three traffic-light circles and their gaps.
    public var trafficLightsWidth: Double {
        (3 * FrameMetrics.trafficLightDiameter + 2 * FrameMetrics.trafficLightGap) * scale
    }

    /// Width of each Windows caption button (minimise, maximise, close).
    public var winButtonWidth: Double { 46 * scale }

    /// Rounded address field of the browser toolbar; nil when the window is too narrow for one.
    public var addressField: LayoutRect? {
        guard kind == .browserWindow, let bar else { return nil }
        let left = FrameMetrics.trafficLightInset * scale + trafficLightsWidth + 64 * scale
        let right = 16 * scale
        let height = 26 * scale
        let width = bar.width - left - right
        guard width >= 40 * scale else { return nil }
        return LayoutRect(x: left, y: bar.midY - height / 2, width: width, height: height)
    }
}
