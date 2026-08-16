import Foundation

/// Structured view of one e-Sword dictionary / lexicon article.
///
/// e-Sword modules carry **no semantic tags** for lemma / pronunciation / glosses —
/// the structure is encoded entirely in inline colors. Verified against the real
/// Spanish library on disk (Strong, Chávez, Swanson, Tuggy, Vine, Ortiz, Multiléxico):
///
/// ```html
/// <p><span style="color:#800080;">לֵב</span></p>                        <- lemma (original script)
/// <p><span style="color:#000080;font-weight:bold;">leb</span></p>       <- PRONUNCIATION
/// <p>forma de <span style="color:#808000;…">H3824</span>;               <- Strong cross-ref
///    <span style="color:#CC3333;">ánimo, corazón, cordura…</span></p>   <- RV1960 Spanish glosses
/// ```
///
/// The palette varies by publisher but the *roles* do not:
///
/// | Role | Colors seen | Modules |
/// |------|-------------|---------|
/// | lemma | `#800080` `#800000` `#0099CC` | Strong, Chávez, Swanson, Tuggy, Vine, Ortiz |
/// | pronunciation | `#000080` (bold) | Strong, Vine, Multiléxico |
/// | Spanish glosses | `#CC3333` | Strong, Multiléxico |
/// | Strong cross-ref | `#808000` + underline | Strong, Vine |
/// | verse cross-ref | `#008000` + underline | Chávez, Vine |
/// | section header | `#008080` bold, centered `<p>` | Multiléxico (6 sub-dictionaries) |
///
/// Reading the structure **before** flattening to plain text is what makes
/// pronunciation and Spanish glosses reliable. The previous approach flattened
/// first and then guessed the pronunciation back out of prose, which required a
/// hand-maintained list of words it must never return.
///
/// Position, not just color, disambiguates: Vine puts the pronunciation *first*
/// (`abares (ἀβαρής, G4)`) while Strong puts it *after* the lemma. Barclay uses the
/// lemma color for a Latin-script headword (`AGAPE`) and green for a Strong ref, so
/// every field is additionally validated by content shape before it is accepted.
///
/// Anything this parser cannot find is returned empty — callers keep their existing
/// plain-text fallbacks, so an unknown module is never worse off than before.
struct LexiconArticle: Hashable, Sendable {

    /// One publisher section inside a compiled module (Multiléxico bundles six).
    struct Section: Hashable, Sendable {
        let title: String
        let plain: String
    }

    /// Hebrew / Greek headword as printed in the article.
    var lemma: String = ""
    /// Latin-letter pronunciation (`leb`, `agápe`, `abares`) — never a gloss or a morph tag.
    var pronunciation: String = ""
    /// RV1960 Spanish glosses, in article order.
    var glosses: [String] = []
    /// Other Strong codes this article points at (`H3824`, `G25`) — tappable cross-links.
    var strongRefs: [String] = []
    /// Publisher sections, when the module compiles several dictionaries into one entry.
    var sections: [Section] = []

    /// True when the structured parse found nothing usable and the caller should fall back.
    var isEmpty: Bool {
        lemma.isEmpty && pronunciation.isEmpty && glosses.isEmpty && sections.isEmpty
    }

    // MARK: - Parse

    /// Articles can be large (Multiléxico bundles ~52 KB per Strong number).
    /// Bound the structural scan the same way `ModuleDatabase` bounds plain text.
    private static let maxParseChars = 200_000

    /// Parse the **raw** module field. Must be given the stored HTML, not plain text.
    static func parse(_ rawDefinition: String) -> LexiconArticle {
        guard !rawDefinition.isEmpty else { return LexiconArticle() }
        let source = rawDefinition.count > maxParseChars
            ? String(rawDefinition.prefix(maxParseChars))
            : rawDefinition

        let spans = scanSpans(source)
        guard !spans.isEmpty else { return LexiconArticle() }

        var article = LexiconArticle()
        article.lemma = findLemma(spans)
        article.pronunciation = findPronunciation(spans, lemma: article.lemma)
        article.glosses = findGlosses(spans)
        article.strongRefs = findStrongRefs(spans, source: source)
        article.sections = findSections(source)
        return article
    }

    // MARK: - Span scanning

    /// One `<span>` with its attributes and decoded inner text.
    private struct Span {
        let color: String       // lowercased hex without `#`, or "" when absent
        let isBold: Bool
        let isItalic: Bool
        let isUnderlined: Bool
        let text: String        // inner tags stripped, entities decoded
        let start: Int          // UTF-16 offset in source, for adjacency tests
        let end: Int
    }

    private static func scanSpans(_ source: String) -> [Span] {
        guard let re = try? NSRegularExpression(
            pattern: #"(?is)<span\b([^>]*)>(.*?)</span>"#,
            options: []
        ) else { return [] }

        var out: [Span] = []
        let ns = NSRange(source.startIndex..., in: source)
        re.enumerateMatches(in: source, options: [], range: ns) { match, _, stop in
            guard let match,
                  match.numberOfRanges > 2,
                  let attrRange = Range(match.range(at: 1), in: source),
                  let innerRange = Range(match.range(at: 2), in: source) else { return }
            let attrs = String(source[attrRange])
            let text = inlineText(String(source[innerRange]))
            out.append(Span(
                color: styleColor(attrs),
                isBold: attrs.range(of: #"(?i)font-weight\s*:\s*bold"#, options: .regularExpression) != nil,
                isItalic: attrs.range(of: #"(?i)font-style\s*:\s*italic"#, options: .regularExpression) != nil,
                isUnderlined: attrs.range(of: #"(?i)text-decoration\s*:[^;"']*underline"#, options: .regularExpression) != nil,
                text: text,
                start: match.range.location,
                end: match.range.location + match.range.length
            ))
            // Hard cap — a pathological article must never stall the study path.
            if out.count >= 4_000 { stop.pointee = true }
        }
        return out
    }

    /// `style="color:#800080;"` or `color="red"` → `800080` / `red`.
    private static func styleColor(_ attrs: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: #"(?i)(?:^|[;\s"'])color\s*[:=]\s*["']?#?([0-9a-fA-F]{3,8}|[a-z]+)"#,
            options: []
        ) else { return "" }
        let ns = NSRange(attrs.startIndex..., in: attrs)
        guard let m = re.firstMatch(in: attrs, options: [], range: ns),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: attrs) else { return "" }
        var hex = String(attrs[r]).lowercased()
        // Expand #rgb → rrggbb so the role tables below only need one form.
        if hex.count == 3, hex.allSatisfy(\.isHexDigit) {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        return hex
    }

    /// Strip nested tags and decode entities inside one span.
    private static func inlineText(_ raw: String) -> String {
        var s = raw.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        s = ESwordText.decodeAllHTMLEntities(s)
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Role palettes

    /// Original-script headword. Purple (Strong Hebrew), maroon (Strong Greek, Vine),
    /// cyan (Chávez, Swanson, Tuggy, Ortiz, Barclay).
    private static let lemmaColors: Set<String> = [
        "800080", "800000", "0099cc", "008080", "4b0082", "6a0dad", "purple", "maroon",
    ]

    /// Pronunciation is navy in every module that marks it at all.
    private static let pronunciationColors: Set<String> = [
        "000080", "00007f", "000090", "191970", "navy",
    ]

    /// RV1960 gloss list at the end of a Strong article.
    private static let glossColors: Set<String> = [
        "cc3333", "c33", "cc0000", "b34d4d",
    ]

    /// Cross-reference colors (olive = Strong, green = verse — but validate by shape).
    private static let crossRefColors: Set<String> = [
        "808000", "008000", "006400", "olive", "green",
    ]

    // MARK: - Field extraction

    /// First span that actually *contains* Hebrew or Greek script.
    /// Colour is used only to break ties, so unknown publishers still resolve.
    private static func findLemma(_ spans: [Span]) -> String {
        var fallback = ""
        for span in spans {
            let t = span.text
            guard isMostlyOriginalScript(t) else { continue }
            if lemmaColors.contains(span.color) {
                return t
            }
            if fallback.isEmpty { fallback = t }
        }
        return fallback
    }

    /// Navy span anywhere (Strong, Vine, Multiléxico), else the italic
    /// parenthetical that sits immediately after the lemma (Swanson, Tuggy).
    private static func findPronunciation(_ spans: [Span], lemma: String) -> String {
        // 1) Explicit navy marking — the publisher told us outright.
        for span in spans where pronunciationColors.contains(span.color) {
            let candidate = trimPronunciation(span.text)
            if StrongResolve.isPlausibleTranslitToken(candidate) {
                return candidate
            }
        }

        // 2) Swanson / Tuggy: `ἀγάπη (agapē), ης (ēs)` — the italic gloss right
        //    after the lemma span. Require adjacency so a later italic Spanish
        //    definition can never be mistaken for a pronunciation.
        guard !lemma.isEmpty,
              let lemmaIndex = spans.firstIndex(where: { $0.text == lemma }) else { return "" }
        let lemmaEnd = spans[lemmaIndex].end
        for span in spans.dropFirst(lemmaIndex + 1) {
            guard span.start - lemmaEnd <= 40 else { break }
            guard span.isItalic else { continue }
            let candidate = trimPronunciation(span.text)
            if StrongResolve.isPlausibleTranslitToken(candidate) {
                return candidate
            }
            break
        }
        return ""
    }

    /// `(agapē),` → `agapē`
    private static func trimPronunciation(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}<>,.;:!?«»\"'“”‹›"))
        // Publishers sometimes print two forms — keep the first word only.
        if let space = t.firstIndex(of: " ") {
            t = String(t[..<space])
        }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: "(),.;:"))
    }

    /// RV1960 Spanish glosses from the marked gloss run.
    private static func findGlosses(_ spans: [Span]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for span in spans where glossColors.contains(span.color) {
            for piece in splitGlossList(span.text) {
                guard StrongResolve.isPlausibleSpanishGloss(piece) else { continue }
                guard piece.count <= 40 else { continue }
                let key = StrongResolve.normalizeLemma(piece)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(piece)
                if out.count >= 16 { return out }
            }
        }
        return out
    }

    private static func splitGlossList(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "—", with: ",")
            .replacingOccurrences(of: "–", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    /// Strong codes this article links to — coloured cross-refs plus any `<num>` tags.
    /// Validated by shape because Barclay uses the *verse* colour for Strong refs.
    private static func findStrongRefs(_ spans: [Span], source: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        func push(_ raw: String) {
            guard let code = StrongResolve.normalizeStrong(raw), !seen.contains(code) else { return }
            seen.insert(code)
            out.append(code)
        }

        for span in spans where crossRefColors.contains(span.color) || span.isUnderlined {
            push(span.text)
            if out.count >= 24 { return out }
        }

        if let re = try? NSRegularExpression(
            pattern: #"(?i)<num>\s*([HG]\s*\d+)\s*</num>"#,
            options: []
        ) {
            let ns = NSRange(source.startIndex..., in: source)
            re.enumerateMatches(in: source, options: [], range: ns) { match, _, stop in
                guard let match, match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: source) else { return }
                push(String(source[r]))
                if out.count >= 24 { stop.pointee = true }
            }
        }
        return out
    }

    /// Split a compiled module (Multiléxico) into its publisher sections.
    /// Header shape: a centered paragraph whose only content is a bold span.
    private static func findSections(_ source: String) -> [Section] {
        guard let re = try? NSRegularExpression(
            pattern: #"(?is)<p[^>]*text-align\s*:\s*center[^>]*>\s*<span([^>]*font-weight\s*:\s*bold[^>]*)>(.*?)</span>\s*</p>"#,
            options: []
        ) else { return [] }

        let ns = NSRange(source.startIndex..., in: source)
        let matches = re.matches(in: source, options: [], range: ns)
        // One centered heading is just a title, not a multi-publisher compilation.
        guard matches.count >= 2 else { return [] }

        var out: [Section] = []
        for (i, match) in matches.enumerated() {
            guard match.numberOfRanges > 2,
                  let titleRange = Range(match.range(at: 2), in: source),
                  let fullRange = Range(match.range, in: source) else { continue }
            let title = inlineText(String(source[titleRange]))
            guard !title.isEmpty else { continue }

            let bodyStart = fullRange.upperBound
            let bodyEnd: String.Index = {
                guard i + 1 < matches.count,
                      let next = Range(matches[i + 1].range, in: source) else { return source.endIndex }
                return next.lowerBound
            }()
            guard bodyStart < bodyEnd else { continue }
            let plain = ESwordText.moduleFieldToPlain(String(source[bodyStart..<bodyEnd]))
            guard !plain.isEmpty else { continue }
            out.append(Section(title: title, plain: plain))
            if out.count >= 24 { break }
        }
        return out
    }

    // MARK: - Script detection

    /// True when the run is predominantly Hebrew or Greek (not a Latin headword
    /// that merely happens to sit in the lemma colour, e.g. Barclay's `AGAPE`).
    private static func isMostlyOriginalScript(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var script = 0
        var latin = 0
        for ch in s {
            if isOriginalScriptCharacter(ch) {
                script += 1
            } else if ch.isLetter {
                latin += 1
            }
        }
        return script >= 1 && script > latin
    }

    private static func isOriginalScriptCharacter(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { sc in
            let v = sc.value
            return (v >= 0x0590 && v <= 0x05FF)   // Hebrew
                || (v >= 0xFB1D && v <= 0xFB4F)   // Hebrew presentation forms
                || (v >= 0x0370 && v <= 0x03FF)   // Greek and Coptic
                || (v >= 0x1F00 && v <= 0x1FFF)   // Greek extended
        }
    }
}
