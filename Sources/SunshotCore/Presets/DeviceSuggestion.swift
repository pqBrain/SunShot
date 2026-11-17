import Foundation

/// A device that suits some media, and how sure the match is.
public struct DeviceSuggestion: Hashable, Sendable {
    public enum Confidence: String, Hashable, Sendable {
        /// The media is exactly one of the device's capture sizes.
        case exact
        /// The media's shape matches the device screen within `DeviceSuggestion.aspectTolerance`.
        case aspect
    }

    /// The catalog model (portrait as drawn); `landscape` says how to turn it.
    public let model: DeviceModel
    public let landscape: Bool
    public let confidence: Confidence

    /// Media whose aspect differs from every screen by more than this gets no suggestion.
    public static let aspectTolerance = 0.03

    /// The selection that shows the media on this device (keeping a finish already chosen).
    public func selection(finish: String = DeviceCatalog.defaultFinishID) -> DeviceSelection {
        DeviceSelection(model: model.id, finish: finish, landscape: landscape)
    }

    private struct Candidate {
        let model: DeviceModel
        let oriented: DeviceModel
        let landscape: Bool
    }

    /// The best device for media of `size` (S12, "suggest the device that matches uploaded media"):
    /// 1. an exact capture size of a device (either orientation for rotatable devices);
    /// 2. else the device whose screen aspect is closest, if within `aspectTolerance`; ties go to the device
    ///    whose recommended size is closest to the media's long side, then catalog order;
    /// 3. else nil (e.g. a window capture that matches no screen).
    public static func suggest(for size: PixelSize, catalog: DeviceCatalog = .bundled) -> DeviceSuggestion? {
        let candidates = catalog.models.flatMap { model in
            let upright = Candidate(model: model, oriented: model, landscape: false)
            return model.rotatable
                ? [upright, Candidate(model: model, oriented: model.rotated(), landscape: true)] : [upright]
        }
        if let exact = candidates.first(where: { $0.oriented.captureSizes.contains(size) }) {
            return DeviceSuggestion(model: exact.model, landscape: exact.landscape, confidence: .exact)
        }
        let aspect = size.aspectRatio
        let longSide = Double(max(size.width, size.height))
        var best: (score: Double, sizeGap: Double, candidate: Candidate)?
        for candidate in candidates {
            let score = abs(log(aspect / candidate.oriented.screenAspect))
            guard score <= log(1 + aspectTolerance) else { continue }
            let recommended = candidate.model.recommendedSize
            let sizeGap = abs(log(longSide / Double(max(recommended.width, recommended.height))))
            if let current = best {
                let tied = abs(current.score - score) <= 1e-9
                if current.score < score - 1e-9 || (tied && current.sizeGap <= sizeGap) { continue }
            }
            best = (score, sizeGap, candidate)
        }
        guard let best else { return nil }
        return DeviceSuggestion(model: best.candidate.model, landscape: best.candidate.landscape, confidence: .aspect)
    }
}
