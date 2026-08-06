import Foundation
import SwiftUI

/// A tappable link found inside dictionary / lexicon / commentary plain text.
enum StudyLink: Hashable, Sendable {
    /// Strong's number, e.g. H3068 / G26
    case strong(String)
    /// Bible reference (verseEnd optional for ranges)
    case verse(book: Int, chapter: Int, verse: Int, verseEnd: Int?)

    var displayLabel: String {
        switch self {
        case .strong(let code):
            return code
        case .verse(let book, let chapter, let verse, let verseEnd):
            if let verseEnd, verseEnd != verse {
                return BibleBooks.reference(book: book, chapter: chapter, verse: verse) + "-\(verseEnd)"
            }
            return BibleBooks.reference(book: book, chapter: chapter, verse: verse)
        }
    }

    /// Custom URL scheme used inside AttributedString links.
    func toURL() -> URL? {
        switch self {
        case .strong(let code):
            return URL(string: "espada-study://strong/\(code)")
        case .verse(let book, let chapter, let verse, let verseEnd):
            let end = verseEnd ?? verse
            return URL(string: "espada-study://verse/\(book)/\(chapter)/\(verse)/\(end)")
        }
    }

    static func from(url: URL) -> StudyLink? {
        guard url.scheme == "espada-study" else { return nil }
        let host = url.host ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "strong", let code = parts.first, StrongNormalizer.looksLikeStrong(code) {
            return .strong(StrongNormalizer.normalize(code))
        }
        if host == "verse", parts.count >= 3,
           let book = Int(parts[0]), let chapter = Int(parts[1]), let verse = Int(parts[2]) {
            let end = parts.count >= 4 ? Int(parts[3]) : verse
            return .verse(book: book, chapter: chapter, verse: verse, verseEnd: end)
        }
        let comps = url.absoluteString
            .replacingOccurrences(of: "espada-study://", with: "")
            .split(separator: "/")
            .map(String.init)
        if comps.first == "strong", comps.count >= 2, StrongNormalizer.looksLikeStrong(comps[1]) {
            return .strong(StrongNormalizer.normalize(comps[1]))
        }
        if comps.first == "verse", comps.count >= 4,
           let book = Int(comps[1]), let chapter = Int(comps[2]), let verse = Int(comps[3]) {
            let end = comps.count >= 5 ? Int(comps[4]) : verse
            return .verse(book: book, chapter: chapter, verse: verse, verseEnd: end)
        }
        return nil
    }
}

/// Finds Strong codes and Bible references in cleaned e-Sword plain text.
/// Covers Spanish + English e-Sword forms: Gén 2:4, Luk 5:27-29, 1Pe 5:13, Gen. 38:11, Php 2:26.
enum StudyLinkParser {

    private struct Match {
        let range: Range<String.Index>
        let link: StudyLink
    }

    /// Cap link scanning so huge dictionary articles cannot freeze or jetsam the app.
    private static let maxLinkScanChars = 48_000

    /// Build an AttributedString with tappable Strong + verse links.
    static func attributed(
        _ plain: String,
        bodyColor: Color,
        linkColor: Color
    ) -> AttributedString {
        let scanSource: String
        if plain.count > maxLinkScanChars {
            scanSource = String(plain.prefix(maxLinkScanChars))
        } else {
            scanSource = plain
        }

        var attr = AttributedString(plain)
        attr.foregroundColor = bodyColor

        let matches = findMatches(in: scanSource)
        for m in matches {
            guard let url = m.link.toURL() else { continue }
            let ns = NSRange(m.range, in: scanSource)
            guard let attrRange = Range(ns, in: attr) else { continue }
            attr[attrRange].link = url
            attr[attrRange].foregroundColor = linkColor
            attr[attrRange].underlineStyle = .single
        }
        return attr
    }

    static func findLinks(in plain: String) -> [StudyLink] {
        findMatches(in: plain).map(\.link)
    }

    private static func findMatches(in plain: String) -> [Match] {
        var matches: [Match] = []

        // Strong: H3068, G26, h430
        if let re = try? NSRegularExpression(pattern: #"\b([HhGg]\d{1,5})\b"#, options: []) {
            let ns = NSRange(plain.startIndex..., in: plain)
            re.enumerateMatches(in: plain, options: [], range: ns) { result, _, _ in
                guard let result,
                      let full = Range(result.range, in: plain),
                      let g1 = Range(result.range(at: 1), in: plain) else { return }
                let code = StrongNormalizer.normalize(String(plain[g1]))
                matches.append(Match(range: full, link: .strong(code)))
            }
        }

        // Universal verse patterns used by e-Sword modules (after HTML strip).
        // 1) "Gén 2:4", "1 Juan 3:16-18", "Php 2:26", "Éxo 17:15"
        // 2) "1Pe 5:13", "1Co 13:4"  (no space after book number)
        // 3) "Gen. 38:11", "Mt. 5:12" (period after abbr)
        // 4) "Luk 5:27-29", "Act 12:12", "Mat 1:16", "Joh 1:1"
        // Optional trailing letter for some Strong bibles is not part of the ref.
        let refPatterns: [String] = [
            // Standard: optional 1/2/3 + letters/period, space, ch:v[-v2]
            #"(?<![\p{L}\p{N}])((?:[123]\s*)?[\p{L}][\p{L}\.]{0,28})\s+(\d{1,3})\s*[:：\.]\s*(\d{1,3})(?:\s*[-–—]\s*(\d{1,3}))?\b"#,
            // Underscore form still present if cleaner missed it: Gén_25:16
            #"(?<![\p{L}\p{N}])((?:[123]\s*)?[\p{L}][\p{L}\.]{0,28})_(\d{1,3})\s*[:：\.]\s*(\d{1,3})(?:\s*[-–—]\s*(\d{1,3}))?\b"#,
        ]

        for pattern in refPatterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let ns = NSRange(plain.startIndex..., in: plain)
            re.enumerateMatches(in: plain, options: [], range: ns) { result, _, _ in
                guard let result,
                      let full = Range(result.range, in: plain),
                      let bookR = Range(result.range(at: 1), in: plain),
                      let chR = Range(result.range(at: 2), in: plain),
                      let vR = Range(result.range(at: 3), in: plain) else { return }

                var bookRaw = String(plain[bookR])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip trailing period: "Gen." → "Gen"
                while bookRaw.hasSuffix(".") {
                    bookRaw = String(bookRaw.dropLast())
                }
                // Reject pure noise / too-short junk before resolve
                let key = BibleBooks.normalizeBookKey(bookRaw)
                guard key.count >= 2 else { return }
                // Avoid matching "v 1:2" / "cap 3:4" style noise
                if ["v", "vs", "vv", "cap", "caps", "ch", "chs", "cf", "ver", "vers", "p", "pp", "n", "nn"].contains(key) {
                    return
                }

                guard let bookNum = BibleBooks.resolveBook(bookRaw),
                      let chapter = Int(plain[chR]),
                      let verse = Int(plain[vR]) else { return }

                var end: Int?
                if result.numberOfRanges > 4, result.range(at: 4).location != NSNotFound,
                   let eR = Range(result.range(at: 4), in: plain) {
                    end = Int(plain[eR])
                }

                if let info = BibleBooks.book(number: bookNum) {
                    if chapter < 1 || chapter > info.chapters { return }
                } else if chapter < 1 || chapter > 150 {
                    return
                }
                if verse < 1 || verse > 200 { return }
                if let end, (end < verse || end > 200) { return }

                matches.append(Match(
                    range: full,
                    link: .verse(book: bookNum, chapter: chapter, verse: verse, verseEnd: end)
                ))
            }
        }

        // Drop overlapping matches (prefer longer / earlier)
        matches.sort { a, b in
            if a.range.lowerBound != b.range.lowerBound {
                return a.range.lowerBound < b.range.lowerBound
            }
            return a.range.upperBound > b.range.upperBound
        }
        var filtered: [Match] = []
        var lastEnd = plain.startIndex
        for m in matches {
            if m.range.lowerBound < lastEnd { continue }
            filtered.append(m)
            lastEnd = m.range.upperBound
        }
        return filtered
    }
}
