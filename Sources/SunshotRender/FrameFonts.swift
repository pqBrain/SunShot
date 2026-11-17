public import CoreText
import Foundation

/// Resolves the font tokens (PostScript names) to Core Text fonts. Sunshot uses system and installed fonts only
/// (no bundled font files, see DECISIONS S5); a name that isn't installed falls back to the system font.
public enum FrameFonts {
    /// The font for `postScriptName` at `size`, or the system UI font when the name is empty or not installed.
    public static func font(_ postScriptName: String, size: Double) -> CTFont {
        if !postScriptName.isEmpty, isAvailable(postScriptName) {
            return CTFontCreateWithName(postScriptName as CFString, size, nil)
        }
        return systemFont(size: size)
    }

    /// The system UI font (used for an empty or missing name).
    public static func systemFont(size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// Whether `postScriptName` names an installed font. The empty name (system font) is always available.
    public static func isAvailable(_ postScriptName: String) -> Bool {
        guard !postScriptName.isEmpty else { return true }
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }
}
