import AppKit
public import SunshotCore

/// A font choice in the Text / Code pickers, stored in the document by PostScript name ("" = system font).
public struct FontOption: Hashable, Identifiable, Sendable {
    public let name: String
    public let postScriptName: String
    public var id: String { postScriptName }

    public init(name: String, postScriptName: String) {
        self.name = name
        self.postScriptName = postScriptName
    }
}

/// Fonts offered by the pickers. Sunshot ships no font files (see DECISIONS S5): the recommended list is the
/// system font plus families every Mac has installed, followed by everything installed on this Mac.
@MainActor
public enum FontLibrary {
    /// Families that come with macOS, listed first (only those actually installed are shown).
    static let recommendedText: [FontOption] = [
        FontOption(name: UIStrings.systemFont, postScriptName: ""),
        FontOption(name: "Helvetica Neue", postScriptName: "HelveticaNeue"),
        FontOption(name: "Avenir Next", postScriptName: "AvenirNext-Regular"),
        FontOption(name: "Georgia", postScriptName: "Georgia"),
    ]
    static let recommendedCode: [FontOption] = [
        FontOption(name: UIStrings.systemMonoFont, postScriptName: ""),
        FontOption(name: "Menlo", postScriptName: "Menlo-Regular"),
        FontOption(name: "Monaco", postScriptName: "Monaco"),
        FontOption(name: "Courier New", postScriptName: "CourierNewPSMT"),
    ]

    public static func recommended(_ role: FontRole) -> [FontOption] {
        (role == .text ? recommendedText : recommendedCode).filter { isAvailable($0.postScriptName) }
    }

    private static var installedCache: [FontRole: [FontOption]] = [:]

    /// Installed families (regular member of each), monospaced only for Code; recommended ones are left out.
    public static func installed(_ role: FontRole) -> [FontOption] {
        if let cached = installedCache[role] { return cached }
        let manager = NSFontManager.shared
        let skip = Set(recommended(role).map(\.postScriptName))
        var options: [FontOption] = []
        for family in manager.availableFontFamilies where !family.hasPrefix(".") {
            guard let members = manager.availableMembers(ofFontFamily: family),
                let member = members.first(where: { ($0[safe: 1] as? String) == "Regular" }) ?? members.first,
                let postScriptName = member.first as? String, !skip.contains(postScriptName)
            else { continue }
            if role == .code {
                let traits = (member[safe: 3] as? NSNumber)?.uintValue ?? 0
                guard traits & NSFontTraitMask.fixedPitchFontMask.rawValue != 0 else { continue }
            }
            options.append(FontOption(name: family, postScriptName: postScriptName))
        }
        installedCache[role] = options
        return options
    }

    /// Whether the font is installed. The empty name (system font) always is.
    public static func isAvailable(_ postScriptName: String) -> Bool {
        postScriptName.isEmpty || NSFont(name: postScriptName, size: 12) != nil
    }

    /// Name shown in the picker for the stored font, or "Font unavailable" when it isn't installed.
    public static func displayName(_ postScriptName: String, role: FontRole) -> String {
        guard isAvailable(postScriptName) else { return UIStrings.fontUnavailable }
        if let option = (recommended(role) + installed(role)).first(where: { $0.postScriptName == postScriptName }) {
            return option.name
        }
        return NSFont(name: postScriptName, size: 12)?.displayName ?? postScriptName
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
