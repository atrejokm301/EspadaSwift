import SwiftUI

/// User-selectable Latin reading fonts for Bible / study body text.
enum ReadingFontFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case googleSansFlex
    case roboto
    case inter
    case robotoFlex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .googleSansFlex: return "Google Sans Flex"
        case .roboto: return "Roboto"
        case .inter: return "Inter"
        case .robotoFlex: return "Roboto Flex"
        }
    }

    /// PostScript names for bundled faces.
    fileprivate var regular: String {
        switch self {
        case .googleSansFlex: return "GoogleSansFlex-Regular"
        case .roboto: return "Roboto-Regular"
        case .inter: return "Inter-Regular"
        case .robotoFlex: return "RobotoFlex-Regular"
        }
    }

    fileprivate var medium: String {
        switch self {
        case .googleSansFlex: return "GoogleSansFlex-Medium"
        case .roboto: return "Roboto-Medium"
        case .inter: return "Inter-Medium"
        case .robotoFlex: return "RobotoFlex-Regular"
        }
    }

    fileprivate var semiBold: String {
        switch self {
        case .googleSansFlex: return "GoogleSansFlex-SemiBold"
        case .roboto: return "Roboto-Medium" // classic Roboto has no SemiBold file
        case .inter: return "Inter-SemiBold"
        case .robotoFlex: return "RobotoFlex-Regular"
        }
    }

    fileprivate var bold: String {
        switch self {
        case .googleSansFlex: return "GoogleSansFlex-Bold"
        case .roboto: return "Roboto-Bold"
        case .inter: return "Inter-Bold"
        case .robotoFlex: return "RobotoFlex-Regular"
        }
    }
}

/// Latin reading faces (user picks in Apariencia).
enum BibleFont {
    /// Active family is resolved via ThemeManager → ReadingFontFamily.
    static func body(size: Double, family: ReadingFontFamily = .googleSansFlex) -> Font {
        .custom(family.regular, size: size)
    }

    static func medium(size: Double, family: ReadingFontFamily = .googleSansFlex) -> Font {
        .custom(family.medium, size: size)
    }

    static func semiBold(size: Double, family: ReadingFontFamily = .googleSansFlex) -> Font {
        .custom(family.semiBold, size: size)
    }

    static func bold(size: Double, family: ReadingFontFamily = .googleSansFlex) -> Font {
        .custom(family.bold, size: size)
    }

    static func caption(size: Double, family: ReadingFontFamily = .googleSansFlex) -> Font {
        .custom(family.semiBold, size: max(11, size - 4))
    }
}

/// Libertinus Serif — **Hebrew and Greek only** (never used for Latin UI / Spanish body).
enum BiblicalScriptFont {
    private static let regular = "LibertinusSerif-Regular"

    static func body(size: Double) -> Font {
        .custom(regular, size: size)
    }
}

// MARK: - Script detection (Hebrew / Greek)

enum ScriptText {
    /// True if the character is Hebrew or Greek (incl. presentation / extended forms).
    static func isHebrewOrGreek(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            if (0x0590...0x05FF).contains(v) { return true } // Hebrew
            if (0xFB1D...0xFB4F).contains(v) { return true } // Hebrew presentation
            if (0x0370...0x03FF).contains(v) { return true } // Greek and Coptic
            if (0x1F00...0x1FFF).contains(v) { return true } // Greek extended
        }
        return false
    }

    /// True if the string is primarily original-language script (not just one letter noise).
    static func isPrimarilyHebrewOrGreek(_ text: String) -> Bool {
        var script = 0
        var letters = 0
        for ch in text where ch.isLetter {
            letters += 1
            if isHebrewOrGreek(ch) { script += 1 }
        }
        guard letters > 0 else { return false }
        return script * 2 >= letters // ≥50% Hebrew/Greek letters
    }

    /// Apply Libertinus Serif to Hebrew/Greek runs; `latin` elsewhere.
    static func attributed(
        _ text: String,
        size: Double,
        latinFamily: ReadingFontFamily,
        color: Color,
        latinWeight: Font.Weight = .regular
    ) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = color
        return applyScriptFonts(
            to: attr,
            source: text,
            size: size,
            latinFamily: latinFamily
        )
    }

    /// Mutates fonts on an existing AttributedString (keeps links / colors).
    static func applyScriptFonts(
        to attr: AttributedString,
        source: String,
        size: Double,
        latinFamily: ReadingFontFamily
    ) -> AttributedString {
        var out = attr
        let latinFont = Font.custom(latinFamily.regular, size: size)
        let scriptFont = BiblicalScriptFont.body(size: size)

        var i = source.startIndex
        while i < source.endIndex {
            let isScript = isHebrewOrGreek(source[i])
            var j = source.index(after: i)
            while j < source.endIndex, isHebrewOrGreek(source[j]) == isScript {
                j = source.index(after: j)
            }
            if let r = Range(NSRange(i..<j, in: source), in: out) {
                out[r].font = isScript ? scriptFont : latinFont
            }
            i = j
        }
        return out
    }
}
