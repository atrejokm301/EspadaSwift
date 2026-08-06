import Foundation

// MARK: - Models (desktop parity)

/// One Strong’s hit resolved from an e-Sword interlinear verse.
struct StrongHit: Codable, Equatable, Hashable, Sendable {
    var strong: String
    var spanish: String
    var greek: String
    var translit: String
    var sourceModule: String
}

/// Result of `resolveStrongs` (Bible word → Strong’s + original script).
struct ResolveStrongsResult: Codable, Equatable, Sendable {
    var word: String
    var hits: [StrongHit]
    var interlinearPath: String
    var interlinearTitle: String
    var note: String

    static func empty(word: String, note: String) -> ResolveStrongsResult {
        ResolveStrongsResult(
            word: word,
            hits: [],
            interlinearPath: "",
            interlinearTitle: "",
            note: note
        )
    }
}

/// One Spanish gloss group parsed from interlinear markup.
struct InterlinearToken: Equatable, Hashable, Sendable {
    var spanish: String
    var strongs: [String]
    var greek: String
    var translit: String
}

// MARK: - Pure resolve pipeline

/// Bible word → Greek/Hebrew via e-Sword interlinear (same design as Asignación del Cielo desktop).
/// Pure parse/match helpers; SQLite load is supplied by the caller / ModuleStore.
enum StrongResolve {

    // MARK: Strong’s normalize

    /// `G 05463` → `G5463`. Returns nil if not H/G + digits.
    /// Only strips **leading** zeros in the number (never trailing: H0430 → H430).
    static func normalizeStrong(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard let first = s.first, first == "G" || first == "H" else { return nil }
        let digits = String(s.dropFirst())
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        var i = digits.startIndex
        while i < digits.endIndex, digits[i] == "0" {
            i = digits.index(after: i)
        }
        let core = i == digits.endIndex ? "0" : String(digits[i...])
        return "\(first)\(core)"
    }

    static func looksLikeStrongCode(_ text: String) -> Bool {
        normalizeStrong(text) != nil
    }

    /// e-Sword / analytical morphology noise — never a Spanish headword or UI label.
    /// Compact: `VqAmSM3`, `vaw3ms`, `NPDSMN`, `VtMISM2`.
    /// Dotted analytical (common in .lexi multi-lex / morph modules):
    /// `subs.pual.ptcp.u.f.sg.a`, `verb.hit.impf.p2.m.pl`, `verb.qal.perf.p3.m.sg`.
    static func isMorphologyCode(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        if looksLikeStrongCode(t) { return false }

        // Dotted analytical morph (can be long — do not cap at 14)
        if isDottedAnalyticalMorph(t) { return true }

        guard t.count <= 14 else { return false }
        // Compact codes: plain Latin alphanumerics only
        guard t.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return false
        }
        let hasDigit = t.contains(where: \.isNumber)
        let hasLetter = t.contains(where: \.isLetter)
        // Letter+digit combos in this app are always morph/tag noise (Spanish has no digits).
        if hasDigit && hasLetter { return true }
        // Short all-letter morph tags after `<num>`: CK, PA, Pu, CC, PL, …
        let u = t.uppercased()
        let shortTags: Set<String> = [
            "CK", "PA", "PU", "CC", "PL", "AG", "RB", "AC", "PC", "PD", "PF", "PG", "PI", "PO",
            "PP", "PR", "PS", "PT", "PV", "N", "V", "A", "D", "C", "P", "R", "T", "I", "S",
            "QAL", "NIF", "PIE", "PUA", "HIF", "HOF", "HIT", "PEAL", "PAEL", "APHEL",
        ]
        if shortTags.contains(u) { return true }
        // Longer morph-only codes without digits (rare)
        if u.count >= 4, u.count <= 10, u == t.uppercased() || t == t.lowercased() {
            if u.hasPrefix("NP") || u.hasPrefix("NC") || u.hasPrefix("VQ") || u.hasPrefix("VT")
                || u.hasPrefix("VP") || u.hasPrefix("VA") || u.hasPrefix("RB") || u.hasPrefix("RP") {
                return true
            }
        }
        return false
    }

    /// Dotted analytical morph tags from multi-lex / morph / OSHB-style modules.
    /// Examples:
    /// - `subs.pual.ptcp.u.f.sg.a`
    /// - `verb.hit.impf.p2.m.pl`
    /// - `nmpr.m.sg.a` (proper name — Multilexical / similar)
    /// - `ncmpa`, when written dotted as `n.m.pl.a`
    ///
    /// Structural (not a fixed head list): 3+ short alphanumeric segments separated by dots.
    static func isDottedAnalyticalMorph(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip trailing punctuation often glued after clean: "nmpr.m.sg.a,"
        let core = t.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}»\"'"))
        guard core.contains("."), core.count >= 5, core.count <= 48 else { return false }
        guard core.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || $0 == "."
        }) else { return false }

        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return false }
        // No empty segments (rejects "a..b")
        guard parts.allSatisfy({ !$0.isEmpty && $0.count <= 8
            && $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
        }) else { return false }

        // Head: short alphabetic POS / type code (nmpr, verb, subs, prep, …)
        let head = parts[0]
        guard head.count >= 1, head.count <= 8, head.allSatisfy(\.isLetter) else { return false }

        // Tail slots are morph abbreviations — almost always very short (m, f, sg, pl, p2, a…)
        let tail = Array(parts.dropFirst())
        let shortTail = tail.filter { $0.count <= 4 }.count
        let morphSlots: Set<String> = [
            "m", "f", "c", "a", "s", "p", "u", "n", "v", "d", "i", "o", "e", "h", "b", "k", "l", "w",
            "sg", "pl", "du", "cs", "abs", "cst", "p1", "p2", "p3", "s1", "s2", "s3",
            "qal", "nif", "pie", "pua", "pual", "hif", "hof", "hit", "peal", "pael", "aphel",
            "perf", "impf", "impv", "ptcp", "part", "inf", "pass", "act", "mid", "pas",
            "wp", "we", "wa", "hap", "shap", "ap", "pr", "pp", "ps", "pc", "pd", "pf", "pg",
            "com", "det", "und", "con", "par", "pro", "suf", "pre",
        ]
        let morphy = tail.filter { morphSlots.contains($0) || $0.count <= 2 }.count

        // Known POS heads (including Multilexical / OSHB nmpr = proper name)
        let heads: Set<String> = [
            "subs", "subst", "n", "noun", "v", "verb", "adj", "adv", "prep", "conj",
            "part", "ptcp", "partc", "pron", "num", "numv", "art", "particle",
            "interj", "inj", "suffix", "pref", "prefix",
            "nmpr", "nm", "ncmp", "ncfs", "ncms", "ncfp", "ncmpa", "ncmsc", "ncfsa",
            "a", "d", "r", "t", "i", "c", "p", "s",
        ]
        if heads.contains(head) { return true }

        // Structural: most tail slots look morph-like (covers unknown heads like nmpr variants)
        if Double(morphy) / Double(max(tail.count, 1)) >= 0.6 { return true }
        if shortTail == tail.count, head.count <= 6 { return true }
        return false
    }

    /// True if the string looks like a real Spanish (or at least human) gloss, not morph.
    static func isPlausibleSpanishGloss(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 1 else { return false }
        if isMorphologyCode(t) { return false }
        if isDottedAnalyticalMorph(t) { return false }
        if looksLikeStrongCode(t) { return false }
        // Must contain a letter
        guard t.contains(where: \.isLetter) else { return false }
        // Reject pure digit strings
        if t.allSatisfy(\.isNumber) { return false }
        // Reject strings that are mostly dotted morph after strip
        if t.contains("."), isDottedAnalyticalMorph(t.replacingOccurrences(of: " ", with: "")) {
            return false
        }
        return true
    }

    // MARK: Lemma normalize + score

    /// Strip tags, decode entities, lowercase, fold Spanish accents, keep alphanumerics.
    static func normalizeLemma(_ input: String) -> String {
        var s = input
        s = stripTags(s)
        s = ESwordText.decodeAllHTMLEntities(s)
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        s = s.lowercased()
        // Explicit Spanish folds (folding may keep ñ depending on locale)
        let map: [Character: Character] = [
            "á": "a", "à": "a", "ä": "a", "â": "a",
            "é": "e", "è": "e", "ë": "e", "ê": "e",
            "í": "i", "ì": "i", "ï": "i", "î": "i",
            "ó": "o", "ò": "o", "ö": "o", "ô": "o",
            "ú": "u", "ù": "u", "ü": "u", "û": "u",
            "ñ": "n",
        ]
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if let m = map[ch] {
                out.append(m)
            } else if ch.isLetter || ch.isNumber {
                out.append(ch)
            }
        }
        return out
    }

    /// Higher is better. 0 = no match.
    /// Handles conjugation drift: deleitate ↔ deleitarás, amó ↔ amar, etc.
    static func scoreTokenMatch(word: String, spanish: String) -> Int {
        if isMorphologyCode(word) || isMorphologyCode(spanish) { return 0 }
        let a = normalizeLemma(word)
        let b = normalizeLemma(spanish)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 100 }
        if a.hasPrefix(b) || b.hasPrefix(a) { return 80 }
        if stemMatch(a, b) { return 75 }
        // Shared prefix: deleitate / deleitaras → "deleita" (7)
        let pref = commonPrefixCount(a, b)
        if pref >= 6 { return 72 }
        if pref >= 5, min(a.count, b.count) <= pref + 4 { return 70 }
        if pref >= 4, min(a.count, b.count) <= 6 { return 65 }
        if a.contains(b) || b.contains(a) { return 50 }
        return 0
    }

    /// Longest-first so `aras` wins over `as` / `ar`.
    private static let spanishEndings: [String] = [
        "ariamos", "ariamos", "ariais", "arian", "arias", "aria",
        "aremos", "areis", "aran", "aras", "ara", "are",
        "asteis", "aron", "aste", "amos", "abas", "aban", "aba",
        "iendo", "ando", "ados", "adas", "idos", "idas", "aros",
        "ais", "eis", "ate", "ete", "ite",
        "aos", "es", "os", "as", "an", "en", "ar", "er", "ir",
    ]

    private static func stemMatch(_ a: String, _ b: String) -> Bool {
        let sa = deepStem(a)
        let sb = deepStem(b)
        guard sa.count >= 4, sb.count >= 4 else { return false }
        return sa == sb || sa.hasPrefix(sb) || sb.hasPrefix(sa)
            || commonPrefixCount(sa, sb) >= 5
    }

    private static func stripEnding(_ s: String) -> String {
        for end in spanishEndings where s.count > end.count + 3 && s.hasSuffix(end) {
            return String(s.dropLast(end.count))
        }
        return s
    }

    /// Strip up to two Spanish endings (deleitaras → deleit).
    private static func deepStem(_ s: String) -> String {
        var t = stripEnding(s)
        if t.count >= 6 {
            let t2 = stripEnding(t)
            if t2.count >= 4 { t = t2 }
        }
        // Common infinitive rebuild: stem + ar if we stripped a verb ending
        return t
    }

    private static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var n = 0
        for (ca, cb) in zip(a, b) {
            if ca != cb { break }
            n += 1
        }
        return n
    }

    // MARK: Parse interlinear markup

    /// Universal Strong-map parse for a verse:
    /// 1) iRV-style reverse interlinear (`<blu>` + `<num>` + Hebrew/Greek)
    /// 2) RV1960+ “con Strong” (`palabra <num>H123</num>`) — used when reading **plain** Reina Valera 1960
    static func parseStrongsMapTokens(_ raw: String) -> [InterlinearToken] {
        let blu = parseInterlinearTokens(raw)
        if !blu.isEmpty { return blu }
        return parseWordStrongTokens(raw)
    }

    /// Parse e-Sword interlinear verse HTML into ordered Spanish gloss tokens.
    /// **Preserves raw markup** — pass Scripture as stored (do not strip tags first).
    static func parseInterlinearTokens(_ raw: String) -> [InterlinearToken] {
        guard !raw.isEmpty else { return [] }
        // Bound work on huge interlinear blobs
        let text = raw.count > 200_000 ? String(raw.prefix(200_000)) : raw

        guard let bluRe = try? NSRegularExpression(
            pattern: #"(?is)<blu>(.*?)</blu>"#,
            options: []
        ) else { return [] }

        let ns = NSRange(text.startIndex..., in: text)
        let bluMatches = bluRe.matches(in: text, options: [], range: ns)
        guard !bluMatches.isEmpty else { return [] }

        var tokens: [InterlinearToken] = []
        var prevBluEnd = text.startIndex

        for match in bluMatches {
            guard let fullRange = Range(match.range, in: text),
                  match.numberOfRanges > 1,
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }

            let bluInner = String(text[contentRange])
            let spanishRaw = cleanInline(bluInner)
            let skipMarks: Set<String> = ["•", "·", "→", "←", "‒", "–", "—"]
            // iRV often marks un-translated particles/pronouns as <blu>•</blu>.
            // Keep the Strong + original script so reverse lookup (tap H859) still works;
            // Spanish can be filled later from the Strong lexicon gloss list.
            let spanish: String = {
                if spanishRaw.isEmpty || skipMarks.contains(spanishRaw) { return "" }
                if !isPlausibleSpanishGloss(spanishRaw) { return "" }
                return spanishRaw
            }()

            let before = String(text[prevBluEnd..<fullRange.lowerBound])
            let strongs = collectStrongs(in: before)
            if strongs.isEmpty {
                prevBluEnd = fullRange.upperBound
                continue
            }

            let greek = lastOriginalScript(in: before)
            // Drop only when there is neither Spanish nor original script
            if spanish.isEmpty && greek.isEmpty {
                prevBluEnd = fullRange.upperBound
                continue
            }

            var translit = lastTranslit(in: before)
            // Never treat morphology tags as transliteration
            if isMorphologyCode(translit) { translit = "" }

            tokens.append(InterlinearToken(
                spanish: spanish,
                strongs: strongs,
                greek: greek,
                translit: translit
            ))
            prevBluEnd = fullRange.upperBound
        }
        return tokens
    }

    /// Parse **RV1960 con números Strong** (and similar) verse text:
    /// `Deléitate <num>H6026</num> … Jehová, <num>H3068</num> … corazón. <num>H3820</num>`
    ///
    /// This is the silent map for **plain** Reina Valera 1960 reading (no tags on the reading Bible).
    /// Each `<num>H/G…</num>` is paired with the last Spanish word before it.
    static func parseWordStrongTokens(_ raw: String) -> [InterlinearToken] {
        guard !raw.isEmpty else { return [] }
        let text = raw.count > 200_000 ? String(raw.prefix(200_000)) : raw

        guard let numRe = try? NSRegularExpression(
            pattern: #"(?i)<num>\s*([HG]\s*\d+)\s*</num>"#,
            options: []
        ) else { return [] }

        let ns = NSRange(text.startIndex..., in: text)
        let matches = numRe.matches(in: text, options: [], range: ns)
        guard !matches.isEmpty else { return [] }

        var tokens: [InterlinearToken] = []
        var prevEnd = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  match.numberOfRanges > 1,
                  let codeRange = Range(match.range(at: 1), in: text),
                  let code = normalizeStrong(String(text[codeRange])) else { continue }

            let before = String(text[prevEnd..<fullRange.lowerBound])
            let spanish = lastSpanishWord(in: before)
            prevEnd = fullRange.upperBound

            guard !spanish.isEmpty, isPlausibleSpanishGloss(spanish) else { continue }

            tokens.append(InterlinearToken(
                spanish: spanish,
                strongs: [code],
                greek: "",
                translit: ""
            ))
        }
        return tokens
    }

    /// Last plausible Spanish word in a chunk (skips morphology codes, bare punctuation).
    private static func lastSpanishWord(in chunk: String) -> String {
        let cleaned = cleanInline(chunk)
        guard !cleaned.isEmpty else { return "" }

        // Prefer Unicode letter runs (handles á é í ó ú ñ)
        guard let wordRe = try? NSRegularExpression(
            pattern: #"[\p{L}][\p{L}\p{M}'’\-]{0,40}"#,
            options: []
        ) else { return "" }

        let ns = NSRange(cleaned.startIndex..., in: cleaned)
        var last = ""
        wordRe.enumerateMatches(in: cleaned, options: [], range: ns) { match, _, _ in
            guard let match, let r = Range(match.range, in: cleaned) else { return }
            let w = String(cleaned[r])
            guard isPlausibleSpanishGloss(w) else { return }
            last = w
        }
        return last
    }

    private static func cleanInline(_ s: String) -> String {
        var t = stripTags(s)
        t = ESwordText.decodeAllHTMLEntities(t)
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // e-Sword often glues punctuation into blu: «mundo,» «Hijo»
        let trail: Set<Character> = [".", ",", ";", ":", "!", "?", "»", "«", "\"", "'", "”", "“"]
        while let last = t.last, trail.contains(last) {
            t.removeLast()
        }
        while let first = t.first, trail.contains(first) {
            t.removeFirst()
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(?is)<[^>]+>"#, options: []) else {
            return s
        }
        let ns = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: ns, withTemplate: " ")
    }

    private static func collectStrongs(in before: String) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: #"(?i)<num>\s*([HG]\s*\d+)\s*</num>"#,
            options: []
        ) else { return [] }
        let ns = NSRange(before.startIndex..., in: before)
        var out: [String] = []
        re.enumerateMatches(in: before, options: [], range: ns) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: before),
                  let code = normalizeStrong(String(before[r])) else { return }
            if !out.contains(code) { out.append(code) }
        }
        return out
    }

    /// Last `<grk>` or `<heb>` in the chunk; strip trailing order digits (`χαίρετε1` → `χαίρετε`).
    private static func lastOriginalScript(in before: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: #"(?is)<(?:grk|heb)(?:\s[^>]*)?>(.*?)</(?:grk|heb)>"#,
            options: []
        ) else { return "" }
        let ns = NSRange(before.startIndex..., in: before)
        var last = ""
        re.enumerateMatches(in: before, options: [], range: ns) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: before) else { return }
            var inner = cleanInline(String(before[r]))
            // Strip trailing verse-order digits (e-Sword: χαίρετε1)
            while let c = inner.last, c.isNumber {
                inner.removeLast()
            }
            last = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return last
    }

    /// Last pure Latin transliteration word after the last original-script close tag and before first `<num>`.
    private static func lastTranslit(in before: String) -> String {
        // Work on the segment after the last </grk> or </heb>
        var segment = before
        if let re = try? NSRegularExpression(
            pattern: #"(?is)</(?:grk|heb)>"#,
            options: []
        ) {
            let ns = NSRange(before.startIndex..., in: before)
            let matches = re.matches(in: before, options: [], range: ns)
            if let last = matches.last, let r = Range(last.range, in: before) {
                segment = String(before[r.upperBound...])
            }
        }
        // Cut at first <num>
        if let numRange = segment.range(of: #"(?i)<num>"#, options: .regularExpression) {
            segment = String(segment[..<numRange.lowerBound])
        }
        // Latin words: ascii letters + accents common in translit (ô ê â etc.) + hyphen
        guard let wordRe = try? NSRegularExpression(
            pattern: #"[A-Za-zÀ-ÖØ-öø-ÿĀ-žÔôÊêÂâĪīŪūĒēŌō\-']{2,}"#,
            options: []
        ) else { return "" }
        let ns = NSRange(segment.startIndex..., in: segment)
        var last = ""
        wordRe.enumerateMatches(in: segment, options: [], range: ns) { match, _, _ in
            guard let match, let r = Range(match.range, in: segment) else { return }
            let w = String(segment[r])
            // Skip morphology-like ALLCAPS+digits leftovers
            if w.count <= 8, w.uppercased() == w, w.contains(where: \.isNumber) { return }
            last = w
        }
        return last
    }

    // MARK: Choose tokens for a tapped word

    /// Score one surface form against all interlinear glosses.
    static func chooseTokens(
        word: String,
        wordIndex: Int?,
        tokens: [InterlinearToken]
    ) -> [InterlinearToken] {
        chooseTokens(probes: [word], wordIndex: wordIndex, tokens: tokens)
    }

    /// Try several surface forms (original, folded, stems) — plain RV1960 vs iRV glosses.
    static func chooseTokens(
        probes: [String],
        wordIndex: Int?,
        tokens: [InterlinearToken]
    ) -> [InterlinearToken] {
        guard !tokens.isEmpty else { return [] }

        var bestScore = 0
        var scored: [(Int, Int, InterlinearToken)] = [] // score, index, token

        for (i, tok) in tokens.enumerated() {
            var sc = 0
            for probe in probes {
                let p = probe.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !p.isEmpty else { continue }
                sc = max(sc, scoreTokenMatch(word: p, spanish: tok.spanish))
            }
            if sc > 0 {
                scored.append((sc, i, tok))
                bestScore = max(bestScore, sc)
            }
        }

        if !scored.isEmpty {
            let tied = scored.filter { $0.0 == bestScore }.map { ($0.1, $0.2) }
            // Prefer exact/high matches; only use wordIndex among ties
            if let wi = wordIndex, wi >= 0 {
                if wi < tied.count {
                    return [tied[wi].1]
                }
                if let hit = tied.first(where: { $0.0 == wi }) {
                    return [hit.1]
                }
            }
            return tied.map(\.1)
        }

        // Positional fallback only when no text match (plain RV filler words often absent in iRV)
        if let wi = wordIndex, wi >= 0, wi < tokens.count {
            return [tokens[wi]]
        }
        return []
    }

    // MARK: Candidate interlinear ranking

    /// Score a Bible module as a **silent Strong map** (higher = better).
    /// Plain RV1960 (no Strong tags) scores 0 — not a map.
    /// RV1960+ / con Strong / iRV are preferred maps while the user **reads** plain RV1960.
    static func interlinearCandidateScore(
        title: String,
        filename: String,
        abbreviation: String,
        hasStrongs: Bool
    ) -> Int {
        let hay = (title + " " + filename + " " + abbreviation).lowercased()
        let isInter = hay.contains("interlineal") || hay.contains("interlinear")
        let isIRV = hay.contains("irv")
        let hasPlus = hay.contains("+") || hay.contains("plus")
        let hasStrongWord = hay.contains("strong") || hay.contains("con_strong") || hay.contains("con strong")
        let isGreek = hay.contains("griego") || hay.contains("greek")
        let isHebrew = hay.contains("hebreo") || hay.contains("hebrew") || hay.contains("tanach")
        // Plain “Reina Valera 1960” without Strong/interlinear must never be a map candidate
        let isPlainOnly = (hay.contains("rv1960") || hay.contains("reina"))
            && hay.contains("1960")
            && !isInter && !isIRV && !hasPlus && !hasStrongWord && !hasStrongs
        if isPlainOnly { return 0 }

        // Core signal required
        let core = isInter || isIRV || hasPlus || hasStrongWord || isGreek || isHebrew || hasStrongs
        guard core else { return 0 }

        var score = 0
        // RV1960+ “con Strong” matches plain RV Spanish word-for-word — best silent map
        if hasPlus && (hay.contains("1960") || hay.contains("rv")) { score += 55 }
        if hasStrongWord && hay.contains("1960") { score += 45 }
        if isInter { score += 50 }
        if isIRV { score += 40 }
        if hasPlus { score += 15 }
        if hasStrongWord { score += 20 }
        if hay.contains("1960") || isIRV { score += 30 }
        if isGreek { score += 10 }
        if isHebrew { score += 5 }
        if hasStrongs { score += 8 }
        return max(score, 4)
    }

    static func rankedInterlinearModules(_ modules: [ModuleInfo]) -> [ModuleInfo] {
        modules
            .filter { $0.kind == .bible && !$0.encrypted }
            .map { mod -> (Int, ModuleInfo) in
                let s = interlinearCandidateScore(
                    title: mod.title,
                    filename: mod.filename,
                    abbreviation: mod.abbreviation,
                    hasStrongs: mod.hasStrongs
                )
                return (s, mod)
            }
            .filter { $0.0 > 0 }
            .sorted { $0.0 > $1.0 }
            .map(\.1)
    }

    /// True when raw Scripture can map Spanish → Strong (iRV blu **or** RV1960+ word+num).
    static func looksLikeInterlinearScripture(_ raw: String) -> Bool {
        let sample = raw.prefix(4_000)
        let hasNum = sample.range(of: #"(?i)<num>\s*[HG]"#, options: .regularExpression) != nil
        let hasBlu = sample.range(of: #"(?i)<blu>"#, options: .regularExpression) != nil
        return hasNum || hasBlu
    }

    // MARK: Resolve (pure when verse raw is provided)

    /// Direct Strong’s code typed/tapped — no interlinear open.
    static func resolveDirectStrong(_ word: String) -> ResolveStrongsResult? {
        guard let code = normalizeStrong(word) else { return nil }
        return ResolveStrongsResult(
            word: word,
            hits: [
                StrongHit(
                    strong: code,
                    spanish: "",
                    greek: "",
                    translit: "",
                    sourceModule: ""
                ),
            ],
            interlinearPath: "",
            interlinearTitle: "",
            note: "código Strong’s directo"
        )
    }

    /// Interlinear tokens whose Strong list includes `code` (H/G, any zero-padding).
    static func tokensMatchingStrong(_ code: String, in tokens: [InterlinearToken]) -> [InterlinearToken] {
        guard let target = normalizeStrong(code) else { return [] }
        return tokens.filter { tok in
            tok.strongs.contains { normalizeStrong($0) == target }
        }
    }

    /// Strong code → Spanish gloss + original script from already-parsed interlinear tokens.
    /// Universal path when the user taps a Strong chip (not a Spanish surface form).
    static func resolveFromStrongCode(
        code: String,
        tokens: [InterlinearToken],
        interlinearPath: String,
        interlinearTitle: String
    ) -> ResolveStrongsResult {
        guard let norm = normalizeStrong(code) else {
            return .empty(word: code, note: "Código Strong’s no válido.")
        }
        let matched = tokensMatchingStrong(norm, in: tokens)
        guard !matched.isEmpty else {
            return ResolveStrongsResult(
                word: norm,
                hits: [
                    StrongHit(
                        strong: norm,
                        spanish: "",
                        greek: "",
                        translit: "",
                        sourceModule: interlinearTitle
                    ),
                ],
                interlinearPath: interlinearPath,
                interlinearTitle: interlinearTitle,
                note: "Strong \(norm) no aparece en el interlineal de este versículo."
            )
        }

        var hits: [StrongHit] = []
        var seenKey = Set<String>()
        for tok in matched {
            let spanish = isPlausibleSpanishGloss(tok.spanish) ? tok.spanish : ""
            let key = "\(norm)|\(spanish)|\(tok.greek)|\(tok.translit)"
            guard !seenKey.contains(key) else { continue }
            seenKey.insert(key)
            hits.append(StrongHit(
                strong: norm,
                spanish: spanish,
                greek: tok.greek,
                translit: isMorphologyCode(tok.translit) ? "" : tok.translit,
                sourceModule: interlinearTitle
            ))
        }
        // Prefer hits that actually have Spanish over bullet-only glosses
        hits.sort { a, b in
            let as_ = isPlausibleSpanishGloss(a.spanish) ? 1 : 0
            let bs = isPlausibleSpanishGloss(b.spanish) ? 1 : 0
            if as_ != bs { return as_ > bs }
            return !a.greek.isEmpty && b.greek.isEmpty
        }
        return ResolveStrongsResult(
            word: hits.first(where: { isPlausibleSpanishGloss($0.spanish) })?.spanish ?? norm,
            hits: hits,
            interlinearPath: interlinearPath,
            interlinearTitle: interlinearTitle,
            note: ""
        )
    }

    // MARK: Lexicon definition helpers (Strong dictionary plain text)

    /// RV1960 Spanish glosses at the end of a Strong dictionary article
    /// (e.g. `…: tú, vosotros.` or `…: burlarse, deleitar, delicadeza.`).
    static func extractSpanishGlossesFromLexiconPlain(_ plain: String) -> [String] {
        let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var candidates: [String] = []

        // 1) Text after the last colon (classic Strong layout before final period)
        if let colon = text.range(of: ":", options: .backwards) {
            var tail = String(text[colon.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop trailing period / semicolons
            while let last = tail.last, ".;".contains(last) {
                tail.removeLast()
            }
            candidates.append(contentsOf: splitGlossList(tail))
        }

        // 2) Whole-text scan for short comma lists that look like Spanish headwords
        if candidates.isEmpty {
            candidates.append(contentsOf: splitGlossList(text))
        }

        var out: [String] = []
        var seen = Set<String>()
        for c in candidates {
            let t = c.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleSpanishGloss(t) else { continue }
            // Skip long definition phrases
            guard t.count <= 40, !t.contains(" i.e"), !t.contains("figurativ") else { continue }
            // Prefer words that are mostly letters (and spaces/hyphens)
            let letters = t.filter(\.isLetter).count
            guard letters >= 2, Double(letters) / Double(max(t.count, 1)) >= 0.55 else { continue }
            let key = normalizeLemma(t)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(t)
            if out.count >= 8 { break }
        }
        return out
    }

    /// First Hebrew or Greek run in a lexicon article (the lemma headword).
    static func extractOriginalHeadwordFromLexiconPlain(_ plain: String) -> String? {
        let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // IMPORTANT: use normal (not raw) strings so \u{…} expands for NSRegularExpression.
        // Hebrew (incl. presentation forms)
        if let re = try? NSRegularExpression(
            pattern: "[\u{0590}-\u{05FF}\u{FB1D}-\u{FB4F}]{2,}",
            options: []
        ) {
            let ns = NSRange(text.startIndex..., in: text)
            if let m = re.firstMatch(in: text, options: [], range: ns),
               let r = Range(m.range, in: text) {
                return String(text[r])
            }
        }
        // Greek (incl. extended)
        if let re = try? NSRegularExpression(
            pattern: "[\u{0370}-\u{03FF}\u{1F00}-\u{1FFF}]{2,}",
            options: []
        ) {
            let ns = NSRange(text.startIndex..., in: text)
            if let m = re.firstMatch(in: text, options: [], range: ns),
               let r = Range(m.range, in: text) {
                return String(text[r])
            }
        }
        return nil
    }

    /// Pronunciation for **any** lexicon module. Priority (most reliable first):
    /// 1) Vine style: `leb ( לֵב , H3820 )`
    /// 2) Strong style right after lemma: `לֵב leb forma de…`
    /// 3) Parenthetical **immediately** after lemma: `ἀγαπάω (agapaō)`
    /// Never picks Spanish glosses like `(figurativamente)` or labels like `transliteración`.
    static func extractTranslitFromLexiconPlain(_ plain: String) -> String? {
        let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1) Vine / Ortiz style: pronunciation BEFORE the Hebrew/Greek in parentheses
        //    leb ( לֵב , H3820 ), corazón
        if let re = try? NSRegularExpression(
            pattern: "(?i)\\b([A-Za-zÀ-ÖØ-öø-ÿĀ-žÂâÊêÎîÔôÛûÄäËëÏïÖöÜüŸÿʾʿ\\-']{2,24})\\s*\\(\\s*[\u{0590}-\u{05FF}\u{0370}-\u{03FF}\u{1F00}-\u{1FFF}\u{FB1D}-\u{FB4F}]",
            options: []
        ) {
            let ns = NSRange(text.startIndex..., in: text)
            if let m = re.firstMatch(in: text, options: [], range: ns),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: text) {
                let tok = String(text[r])
                if isPlausibleTranslitToken(tok) { return tok }
            }
        }

        // 2) After first Hebrew/Greek lemma run — scan forward a short window for a real translit.
        //    Skip junk labels: LXX, MT, DSS, forma, etc. (Strong+ / BDB-Thayer style often has
        //    `לֵב LXX …` or `לֵב (LXX …)` before or instead of putting `leb` first.)
        guard let scriptRange = firstScriptRunRange(in: text) else { return nil }
        let windowEnd = text.index(scriptRange.upperBound, offsetBy: 80, limitedBy: text.endIndex)
            ?? text.endIndex
        let window = String(text[scriptRange.upperBound..<windowEnd])

        // 2a) Parenthetical right after lemma: (agapaō) or (LXX καρδία) — only accept real translit
        if let open = window.firstIndex(of: "("),
           let close = window[open...].firstIndex(of: ")") {
            let inner = String(window[window.index(after: open)..<close])
            if let latin = bestTranslitCandidate(in: inner) {
                return latin
            }
        }

        // 2b) Bare Latin tokens after lemma, skipping scholarly tags (LXX, MT, …)
        if let latin = bestTranslitCandidate(in: window) {
            return latin
        }
        return nil
    }

    /// First plausible pronunciation token in a short post-lemma window.
    /// After a scholarly tag like `LXX`, skip the next Latin token (usually the Greek
    /// equivalent name, e.g. `kardía`) so we can still land on Hebrew `leb`.
    private static func bestTranslitCandidate(in snippet: String) -> String? {
        var i = snippet.startIndex
        var guardCount = 0
        var skipNextLatinAfterScholarly = false
        while i < snippet.endIndex, guardCount < 16 {
            guardCount += 1
            // skip non-letters (and Greek/Hebrew script in the window)
            while i < snippet.endIndex {
                let ch = snippet[i]
                if ch.isLetter, !isHebrewOrGreekScalar(ch) { break }
                i = snippet.index(after: i)
            }
            guard i < snippet.endIndex else { return nil }
            guard let tok = readLatinToken(from: snippet, at: i) else { return nil }
            let advance = snippet.index(i, offsetBy: tok.count, limitedBy: snippet.endIndex) ?? snippet.endIndex
            i = advance

            let lower = tok.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))

            // Strong+ / BDB: "LXX …" introduces Greek; next latin is often not the Hebrew sound
            if isScholarlyEditionTag(lower) {
                skipNextLatinAfterScholarly = true
                continue
            }
            if skipNextLatinAfterScholarly {
                skipNextLatinAfterScholarly = false
                continue
            }
            if isPlausibleTranslitToken(tok) { return tok }
        }
        return nil
    }

    private static func isScholarlyEditionTag(_ lower: String) -> Bool {
        let tags: Set<String> = [
            "lxx", "sept", "septuagint", "septuaginta", "mt", "bhs", "bhk", "bhq",
            "dss", "qere", "ketiv", "ktiv", "na", "na28", "ubs", "wh", "tr", "byz",
            "tvm", "bdb", "thayer", "ditat", "twot", "tdnt", "dblhebr", "dbl",
        ]
        return tags.contains(lower)
    }

    private static func firstScriptRunRange(in text: String) -> Range<String.Index>? {
        var i = text.startIndex
        var start: String.Index?
        while i < text.endIndex {
            if isHebrewOrGreekScalar(text[i]) {
                if start == nil { start = i }
            } else if let s = start {
                return s..<i
            }
            i = text.index(after: i)
        }
        if let s = start { return s..<text.endIndex }
        return nil
    }

    private static func isHebrewOrGreekScalar(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { sc in
            let v = sc.value
            return (v >= 0x0590 && v <= 0x05FF)
                || (v >= 0x0370 && v <= 0x03FF)
                || (v >= 0x1F00 && v <= 0x1FFF)
                || (v >= 0xFB1D && v <= 0xFB4F)
        }
    }

    private static func containsHebrewOrGreek(_ s: String) -> Bool {
        s.contains { isHebrewOrGreekScalar($0) }
    }

    private static func firstLatinToken(in s: String) -> String? {
        var i = s.startIndex
        // skip to first Latin letter
        while i < s.endIndex {
            let ch = s[i]
            if ch.isLetter, !isHebrewOrGreekScalar(ch) { break }
            i = s.index(after: i)
        }
        return readLatinToken(from: s, at: i)
    }

    private static func readLatinToken(from text: String, at start: String.Index) -> String? {
        guard start < text.endIndex else { return nil }
        var i = start
        var out = ""
        while i < text.endIndex {
            let ch = text[i]
            if isHebrewOrGreekScalar(ch) { break }
            if ch.isLetter || ch == "-" || ch == "'" || ch == "’" || ch == "ʻ"
                || ch == "ʾ" || ch == "ʿ" {
                out.append(ch)
                i = text.index(after: i)
            } else {
                break
            }
        }
        return out.isEmpty ? nil : out
    }

    /// True Latin-letter **pronunciation** (leb, al, agapao, Yejová).
    /// Never Spanish gloss, English gloss, or Bible book scraps from refs like `( Eze 4:18 )`.
    static func isPlausibleTranslitToken(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"«»“”"))
        guard t.count >= 2, t.count <= 24 else { return false }
        if looksLikeStrongCode(t) { return false }
        if isMorphologyCode(t) || isDottedAnalyticalMorph(t) { return false }
        if containsHebrewOrGreek(t) { return false }

        let lower = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))

        // Bible book abbreviations from verse refs in Chávez / Tuggy / etc. (NOT pronunciation)
        // e.g. Eze, Jer, Gen, 2Re → "Re", Mat, Hch…
        if isBibleBookAbbreviationToken(lower) { return false }
        if BibleBooks.resolveBook(t) != nil || BibleBooks.resolveBook(lower) != nil {
            return false
        }

        // Scholarly edition / text-critical tags (Strong+, BDB, Thayer…) — NOT pronunciation
        if isScholarlyEditionTag(lower) { return false }
        let moreTags: Set<String> = [
            "ub", "str", "strongs", "gk", "hb", "heb", "grk", "gr", "ar", "aram",
            "nm", "nf", "mpl", "fpl", "msg", "fsg",
        ]
        if moreTags.contains(lower) { return false }

        // Hard reject — fake “pronunciations” we actually showed in the UI
        let banned: Set<String> = [
            "transliteration", "transliteracion", "transliteración", "translit", "transliterate",
            "figurativamente", "figurative", "figuratively", "figurat", "ampliamente", "widely",
            "similarly", "similarmente", "tambien", "también", "however", "sinembargo",
            "corazon", "corazón", "heart", "mind", "love", "mente", "voluntad", "sentimientos",
            "forma", "form", "used", "usado", "usada", "compare", "comparar", "compárese",
            "diccionario", "strong", "swanson", "tuggy", "vine", "chavez", "chavez",
            "lo", "la", "los", "las", "de", "del", "en", "un", "una", "por", "para",
            "con", "que", "como", "sobre", "desde", "hasta", "plural", "singular", "el",
            "nombre", "name", "auto", "existente", "eterno", "nacional", "centro", "center",
            "corazon", "vitalidad", "motivaciones", "intenciones", "pensamientos",
            "probably", "probable", "origin", "origem", "foreign", "estrangeira",
        ]
        if banned.contains(lower) { return false }
        if lower.hasPrefix("translit") { return false }
        if lower.hasPrefix("figura") { return false }
        if lower.hasSuffix("mente") || lower.hasSuffix("cion") || lower.hasSuffix("tion")
            || lower.hasSuffix("amente") || lower.hasSuffix("ively")
            || lower.hasSuffix("ingly") || lower.hasSuffix("acion") {
            return false
        }

        let ok = t.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'" || $0 == "’"
                || $0 == "ʻ" || $0 == "ʾ" || $0 == "ʿ"
        }.count
        guard Double(ok) / Double(max(t.count, 1)) >= 0.9 else { return false }

        // Compact scholarly forms only (leb, lebab, yehovah, agapao…)
        if t.count > 16 { return false }

        // 2-letter Hebrew preposition / particle translits only (not "Re", "Ez", "Jn")
        if t.count == 2 {
            let hebp: Set<String> = [
                "al", "el", "im", "et", "ki", "lo", "li", "ba", "be", "le", "mi", "ka",
                "hu", "hi", "an", "od", "ad", "or", "oy", "ei", "av", "iv",
            ]
            return hebp.contains(lower)
        }
        // 3-letter: allow real translits (leb, eth, ben…) but not book codes (eze, jer, gen…)
        if t.count == 3, isBibleBookAbbreviationToken(lower) {
            return false
        }
        return true
    }

    /// Spanish/English Bible book scraps that appear in parentheses after senses in Chávez etc.
    private static func isBibleBookAbbreviationToken(_ lower: String) -> Bool {
        let books: Set<String> = [
            // Spanish
            "gen", "exo", "ex", "lev", "num", "dt", "deu", "jos", "jue", "rut",
            "1s", "2s", "1sa", "2sa", "1r", "2r", "1re", "2re", "re", "1cr", "2cr",
            "esd", "neh", "est", "job", "sal", "sl", "pr", "prv", "ec", "eclesiast",
            "can", "cnt", "is", "isa", "jer", "lm", "lam", "eze", "ez", "ezq", "ezeq",
            "dn", "dan", "os", "jl", "am", "abd", "jon", "mi", "na", "hab", "sof",
            "hag", "zac", "mal",
            "mt", "mat", "mc", "mr", "mar", "lc", "luc", "jn", "jua", "hch", "act",
            "ro", "rom", "1co", "2co", "gl", "gal", "ef", "eph", "fil", "flp", "col",
            "1ts", "2ts", "1ti", "2ti", "tit", "flm", "fm", "he", "heb", "stg", "sant",
            "1p", "2p", "1pe", "2pe", "1jn", "2jn", "3jn", "jud", "ap", "apoc", "apo",
            // English
            "ge", "exod", "levit", "num", "deut", "josh", "judg", "ruth",
            "1sam", "2sam", "1ki", "2ki", "1kgs", "2kgs", "ki", "1ch", "2ch",
            "ezr", "neh", "est", "ps", "psa", "prov", "eccl", "song",
            "isa", "jer", "lam", "ezek", "eze", "dan", "hos", "joel", "amos",
            "obad", "jonah", "mic", "nah", "hab", "zeph", "hag", "zech", "mal",
            "matt", "mark", "luke", "john", "acts", "rom", "1cor", "2cor", "gal",
            "eph", "phil", "col", "1thess", "2thess", "1tim", "2tim", "titus",
            "phlm", "heb", "jas", "1pet", "2pet", "1john", "2john", "3john",
            "jude", "rev",
        ]
        return books.contains(lower)
    }

    private static func splitGlossList(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "—", with: ",")
            .replacingOccurrences(of: "–", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Resolve using pre-parsed tokens from one interlinear module.
    static func resolveFromTokens(
        word: String,
        wordIndex: Int?,
        tokens: [InterlinearToken],
        interlinearPath: String,
        interlinearTitle: String,
        wordProbes: [String] = []
    ) -> ResolveStrongsResult {
        // Typed/tapped Strong code → reverse lookup in this verse (Spanish + original)
        if let code = normalizeStrong(word) {
            let fromCode = resolveFromStrongCode(
                code: code,
                tokens: tokens,
                interlinearPath: interlinearPath,
                interlinearTitle: interlinearTitle
            )
            if fromCode.hits.contains(where: {
                isPlausibleSpanishGloss($0.spanish) || !$0.greek.isEmpty
            }) {
                return fromCode
            }
            // Fall through to empty-ish direct if verse has no match
            return fromCode
        }

        var probes = wordProbes
        if probes.isEmpty { probes = [word] }
        if !probes.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            probes.insert(word, at: 0)
        }

        let chosen = chooseTokens(probes: probes, wordIndex: wordIndex, tokens: tokens)
        if chosen.isEmpty {
            let title = interlinearTitle.isEmpty ? "interlineal" : interlinearTitle
            return ResolveStrongsResult(
                word: word,
                hits: [],
                interlinearPath: interlinearPath,
                interlinearTitle: interlinearTitle,
                note: "«\(word)» no aparece en el interlineal de este versículo (\(title))."
            )
        }

        var hits: [StrongHit] = []
        var seen = Set<String>()
        for tok in chosen {
            for code in tok.strongs {
                guard !seen.contains(code) else { continue }
                seen.insert(code)
                hits.append(StrongHit(
                    strong: code,
                    spanish: tok.spanish,
                    greek: tok.greek,
                    translit: tok.translit,
                    sourceModule: interlinearTitle
                ))
            }
        }

        return ResolveStrongsResult(
            word: word,
            hits: hits,
            interlinearPath: interlinearPath,
            interlinearTitle: interlinearTitle,
            note: hits.isEmpty
                ? "«\(word)» no aparece en el interlineal de este versículo (\(interlinearTitle))."
                : ""
        )
    }

    /// Full multi-candidate resolve given raw verse strings keyed by path.
    /// `verseLoader` returns raw Scripture (tags preserved) or nil.
    /// Accepts Spanish surface forms **or** Strong codes (reverse: code → Spanish + original).
    static func resolveStrongs(
        bookNumber: Int,
        chapter: Int,
        verse: Int,
        word: String,
        wordIndex: Int?,
        candidates: [(path: String, title: String)],
        verseLoader: (String, Int, Int, Int) -> String?
    ) -> ResolveStrongsResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        // Do NOT short-circuit Strong codes here — reverse-lookup needs interlinear tokens
        // so the lexicon card can show Spanish + Hebrew/Greek for every H/G tap.

        guard !candidates.isEmpty else {
            // No interlinear: still accept a bare Strong code so lexicon can open the entry
            if let direct = resolveDirectStrong(trimmed) {
                return direct
            }
            return .empty(
                word: trimmed,
                note: "No hay Biblia interlineal (p. ej. iRV 1960+). Instálala para mapear español → griego/hebreo."
            )
        }

        var lastNote = ""
        var lastPath = ""
        var lastTitle = ""

        for cand in candidates {
            guard let raw = verseLoader(cand.path, bookNumber, chapter, verse) else {
                lastNote = "No se pudo leer el versículo en \(cand.title)."
                lastPath = cand.path
                lastTitle = cand.title
                continue
            }
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastNote = "Versículo vacío en \(cand.title)."
                lastPath = cand.path
                lastTitle = cand.title
                continue
            }
            if ESwordText.looksEncrypted(raw) {
                lastNote = "Módulo cifrado o ilegible: \(cand.title)."
                lastPath = cand.path
                lastTitle = cand.title
                continue
            }
            if !looksLikeInterlinearScripture(raw) {
                lastNote = "\(cand.title) no parece un interlineal con Strong’s."
                lastPath = cand.path
                lastTitle = cand.title
                continue
            }

            let tokens = parseStrongsMapTokens(raw)
            let result = resolveFromTokens(
                word: trimmed,
                wordIndex: wordIndex,
                tokens: tokens,
                interlinearPath: cand.path,
                interlinearTitle: cand.title
            )
            if !result.hits.isEmpty {
                return result
            }
            lastNote = result.note
            lastPath = cand.path
            lastTitle = cand.title
        }

        return ResolveStrongsResult(
            word: trimmed,
            hits: [],
            interlinearPath: lastPath,
            interlinearTitle: lastTitle,
            note: lastNote.isEmpty
                ? "«\(trimmed)» no aparece en el interlineal de este versículo."
                : lastNote
        )
    }
}
