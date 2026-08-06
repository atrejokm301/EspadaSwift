import Foundation

/// Universal e-Sword module text decoder.
///
/// Port of the production Espada Mac pipeline (`Espada3.7/src-tauri/src/text.rs`)
/// plus Espada Mobile named-entity decode (`textarea.innerHTML`).
///
/// Validated against real `.bbli` / `.cmti` / `.dcti` / `.lexi` modules:
/// HTML + full named entities (`&aacute;`), numeric/`&#x…;`, RTF (Windows-1252),
/// e-Sword tags (`num`, `ref`, `red`, `blu`, `grk`, `heb`, purple Strong spans).
///
/// Pipeline (order matters — same as Mac):
/// 1. Bound size / strip NULs
/// 2. RTF → text (Windows-1252 hex bytes, like Mac `encoding_rs::WINDOWS_1252`)
/// 3. Protect Strong / ref / WOC / blu markers
/// 4. Structural HTML breaks → newlines
/// 5. Decode all HTML entities (numeric + full HTML5 named map)
/// 6. Strip remaining tags (content of grk/heb/lat kept — never deleted)
/// 7. Second entity pass + whitespace cleanup
enum ESwordText {

    // MARK: - Public API

    static func looksEncrypted(_ sample: String) -> Bool {
        guard sample.count >= 8 else { return false }
        let limit = min(sample.count, 200)
        var bad = 0
        for ch in sample.prefix(limit) {
            let c = ch.unicodeScalars.first?.value ?? 0
            if c < 9 || c == 0xFFFD || (c < 32 && c != 10 && c != 13 && c != 9) {
                bad += 1
            }
        }
        return bad * 100 / limit > 30
    }

    /// Clean a raw module field for verse tokenization (keeps STRONG/REF/WOC/BLU markers).
    static func cleanToMarkers(_ raw: String) -> String {
        decodeModuleField(raw, keepMarkers: true)
    }

    /// Fully plain text for UI (definitions, commentaries, tooltips).
    static func toPlain(_ marked: String) -> String {
        var s = marked
        s = replace(s, pattern: #"⟦STRONG:([HG]\d+)⟧"#) { $0[1] }
        s = replace(s, pattern: #"⟦BLU:([^⟧]*)⟧"#) { $0[1] }
        s = replace(s, pattern: #"⟦REF:([^⟧]*)⟧"#) { $0[1] }
        s = s.replacingOccurrences(of: "⟦WOC⟧", with: "")
        s = s.replacingOccurrences(of: "⟦/WOC⟧", with: "")
        s = s.replacingOccurrences(of: "⟦BLU⟧", with: "")
        s = s.replacingOccurrences(of: "⟦/BLU⟧", with: "")
        s = stripTags(s)
        // Entities may remain if called on raw HTML
        s = decodeAllHTMLEntities(s)
        s = stripMorphologyNoise(s)
        s = collapseWhitespace(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One-shot: module field → readable plain text (dict / lex / commentary).
    static func moduleFieldToPlain(_ raw: String) -> String {
        polishStudyPlain(toPlain(decodeModuleField(raw, keepMarkers: false)))
    }

    /// Humanize study-module shorthand that confuses readers (especially Swanson / multi-lex).
    /// - `LN 25.43` → `Louw-Nida 25.43` (semantic domain codes — **not** pronunciation)
    /// - Keeps real transliteration in parentheses, e.g. `(agapaō)`, `(adelphē)`, `al`
    static func polishStudyPlain(_ plain: String) -> String {
        guard !plain.isEmpty else { return plain }
        var s = plain

        // Swanson / multi-lex: "1. LN 25.43 amar" → "1. Louw-Nida 25.43 amar"
        // Also "LN10.50" glued forms
        s = replace(s, pattern: #"(?i)\bLN\s*(\d+(?:\.\d+)*)\b"#) { m in
            "Louw-Nida \(m[1])"
        }
        // Bare "LN" still standing alone before a domain (after partial clean)
        s = replace(s, pattern: #"(?i)\bLN\b(?=\s+\d)"#) { _ in "Louw-Nida" }

        // Occasional full misspellings already expanded in some ports
        s = replace(s, pattern: #"(?i)\blouwnida\b"#) { _ in "Louw-Nida" }
        s = replace(s, pattern: #"(?i)\blouw\s*[-–—]?\s*nida\b"#) { _ in "Louw-Nida" }

        s = collapseWhitespace(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove analytical / e-Sword morphology tags that some .lexi modules dump into definitions.
    /// Examples stripped (any module — Multilexical, morph packs, iRV leftovers):
    /// - `subs.pual.ptcp.u.f.sg.a`
    /// - `verb.hit.impf.p2.m.pl`
    /// - `nmpr.m.sg.a` (proper name)
    /// - `VqAmSM3`, `VtMISM2`, `vaw3ms`, `NPDSMN`
    static func stripMorphologyNoise(_ plain: String) -> String {
        guard !plain.isEmpty else { return plain }
        var s = plain

        // 1) Universal dotted morph: head + 2+ short segments
        //    Matches nmpr.m.sg.a, verb.hit.impf.p2.m.pl, subs.pual.ptcp… without a head whitelist.
        s = replace(
            s,
            pattern: #"(?i)\b[a-z]{1,8}(?:\.[a-z0-9]{1,6}){2,}\b"#
        ) { m in
            // Keep rare false positives that look like real abbreviations (none expected in Spanish Bible modules)
            let tok = m[0]
            if StrongResolve.isDottedAnalyticalMorph(tok) || StrongResolve.isMorphologyCode(tok) {
                return " "
            }
            // Structural: 3+ short alpha segments → morph noise in this domain
            let parts = tok.split(separator: ".")
            if parts.count >= 3, parts.allSatisfy({ $0.count <= 6 }) {
                return " "
            }
            return tok
        }

        // 2) Compact e-Sword morph after Strongs: VqAmSM3, VtMISM2, NPDSMN, vaw3ms, RBPM3
        s = replace(
            s,
            pattern: #"\b(?![HG]\d{1,5}\b)(?=[A-Za-z]*\d)[A-Za-z]{1,10}\d[A-Za-z0-9]{0,8}\b"#
        ) { m in
            StrongResolve.isMorphologyCode(m[0]) ? " " : m[0]
        }

        // 2b) Token scan — catches morph glued to punctuation: "nmpr.m.sg.a," / "(verb.qal…)"
        s = s.split(whereSeparator: { $0.isWhitespace }).map { part -> String in
            let raw = String(part)
            let tok = raw.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            if StrongResolve.isMorphologyCode(tok) || StrongResolve.isDottedAnalyticalMorph(tok) {
                return " "
            }
            // Also strip if the core of a punctuated token is dotted morph
            if tok.contains("."),
               (StrongResolve.isDottedAnalyticalMorph(tok)
                || tok.split(separator: ".").count >= 3) {
                let segs = tok.split(separator: ".")
                if segs.count >= 3, segs.allSatisfy({ $0.count <= 6 && $0.allSatisfy({ $0.isLetter || $0.isNumber }) }) {
                    return " "
                }
            }
            return raw
        }.joined(separator: " ")

        // 3) Standalone stem names that appear as their own token
        s = replace(
            s,
            pattern: #"\b(?:QAL|NIFAL|PIEL|PUAL|HIFIL|HOFAL|HITPAEL|HITPAEL|PEAL|PAEL|APHEL|NIF|PIE|PUA|HIF|HOF|HIT)\b"#
        ) { _ in " " }

        // 4) Colon glue after Hebrew when morph was removed: "עַל : " → "עַל "
        s = replace(s, pattern: #"\s*:\s*(?=\s|$|[,;.])"#) { _ in " " }
        s = replace(s, pattern: #"(?m)^[ \t]*:[ \t]*"#) { _ in "" }

        return s
    }

    /// Cheap check: skip the heavy WOC pipeline when the verse has no red-letter markup.
    static func rawLikelyHasWordsOfChrist(_ raw: String) -> Bool {
        // Avoid lowercasing multi‑KB interlinear blobs — substring probes are enough.
        raw.contains("<red") || raw.contains("<RED") || raw.contains("</red")
            || raw.contains("B34D4D") || raw.contains("b34d4d")
            || raw.contains("⟦WOC")
            || raw.contains("ff0000") || raw.contains("FF0000")
            || raw.contains("c00000") || raw.contains("C00000")
    }

    /// Reading runs for Bible UI: plain text chunks with Words-of-Christ flags.
    /// Use everywhere verse body is shown so red letters work in reading *and* study mode.
    static func readingRuns(from raw: String) -> [BibleTextRun] {
        if !rawLikelyHasWordsOfChrist(raw) {
            let plain = moduleFieldToPlain(raw)
            return plain.isEmpty ? [] : [BibleTextRun(text: plain, isWordsOfChrist: false)]
        }
        let marked = cleanToMarkers(raw)
        guard !marked.isEmpty else { return [] }

        var runs: [BibleTextRun] = []
        var inWOC = false
        var buffer = ""
        var i = marked.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(BibleTextRun(text: buffer, isWordsOfChrist: inWOC))
            buffer = ""
        }

        while i < marked.endIndex {
            if marked[i...].hasPrefix("⟦WOC⟧") {
                flush()
                inWOC = true
                i = marked.index(i, offsetBy: 5)
                continue
            }
            if marked[i...].hasPrefix("⟦/WOC⟧") {
                flush()
                inWOC = false
                i = marked.index(i, offsetBy: 6)
                continue
            }
            if marked[i...].hasPrefix("⟦STRONG:") {
                if let end = marked[i...].range(of: "⟧") {
                    // Reading view: omit Strong codes (shown as chips only in study mode)
                    i = end.upperBound
                    continue
                }
            }
            if marked[i...].hasPrefix("⟦BLU:") {
                if let end = marked[i...].range(of: "⟧") {
                    let inner = marked[marked.index(i, offsetBy: 5)..<end.lowerBound]
                    buffer += inner
                    i = end.upperBound
                    continue
                }
            }
            if marked[i...].hasPrefix("⟦REF:") {
                if let end = marked[i...].range(of: "⟧") {
                    let inner = marked[marked.index(i, offsetBy: 5)..<end.lowerBound]
                    buffer += inner
                    i = end.upperBound
                    continue
                }
            }
            // Drop any other marker residue
            if marked[i] == "⟦", let end = marked[i...].range(of: "⟧") {
                i = end.upperBound
                continue
            }
            buffer.append(marked[i])
            i = marked.index(after: i)
        }
        flush()

        // Merge adjacent runs with the same WOC flag
        var merged: [BibleTextRun] = []
        for run in runs {
            if let last = merged.last, last.isWordsOfChrist == run.isWordsOfChrist {
                merged[merged.count - 1] = BibleTextRun(
                    text: last.text + run.text,
                    isWordsOfChrist: last.isWordsOfChrist
                )
            } else {
                merged.append(run)
            }
        }
        return merged.filter { !$0.text.isEmpty }
    }

    /// True when a CSS/HTML color is a Words-of-Christ red (not purple Strong / gray).
    static func isWordsOfChristColor(_ raw: String) -> Bool {
        let c = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "#", with: "")
        if ["red", "maroon", "crimson", "darkred", "firebrick", "indianred"].contains(c) {
            return true
        }
        // Expand #rgb → rrggbb
        let hex: String
        if c.count == 3, c.allSatisfy(\.isHexDigit) {
            hex = c.map { "\($0)\($0)" }.joined()
        } else if c.count >= 6, c.prefix(6).allSatisfy(\.isHexDigit) {
            hex = String(c.prefix(6))
        } else {
            return Self.knownWOCHex.contains(c)
        }
        if Self.knownWOCHex.contains(hex) { return true }
        guard let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(4).prefix(2), radix: 16) else {
            return false
        }
        // Dominant red (covers e-Sword #B34D4D). Excludes purple Strong (#804DB3) and gray.
        let ri = Int(r), gi = Int(g), bi = Int(b)
        return ri >= 0x90 && gi <= 0x70 && bi <= 0x70 && ri > gi + 0x20 && ri > bi + 0x20
    }

    /// Common e-Sword / publisher red-letter palette.
    private static let knownWOCHex: Set<String> = [
        "ff0000", "c00000", "800000", "cc0000", "e85d5d", "b34d4d",
        "b22222", "a52a2a", "dc143c", "cd5c5c", "c41e3a", "990000",
        "aa0000", "bb0000", "cc3333", "d32f2f", "c0392b", "e74c3c",
        "9b111e", "a40000", "b30000"
    ]

    // MARK: - Core pipeline (matches Espada Mac `clean_esword_text`)

    private static func decodeModuleField(_ raw: String, keepMarkers: Bool) -> String {
        guard !raw.isEmpty else { return "" }

        // Bound work — never hang/crash on multi‑MB blobs
        var s = raw.count > 400_000 ? String(raw.prefix(400_000)) : raw
        s = stripNulls(s)

        // Classic RTF (legacy modules / Details.Comments)
        if s.contains("\\rtf") || (s.hasPrefix("{") && s.contains("\\f")) {
            s = rtfToText(s)
        }

        // Drop <style> / <script> / <head> blocks (common in e-Sword HTML)
        s = replace(s, pattern: #"(?is)<style[^>]*>.*?</style>"#) { _ in " " }
        s = replace(s, pattern: #"(?is)<script[^>]*>.*?</script>"#) { _ in " " }
        s = replace(s, pattern: #"(?is)<head[^>]*>.*?</head>"#) { _ in " " }

        // --- Protect e-Sword semantic tags (before any tag strip) ---

        // <num>H3068</num>  /  <num>G26</num>
        s = replace(s, pattern: #"(?i)<num>\s*([HG]\d+)\s*</num>"#) { m in
            keepMarkers ? "⟦STRONG:\(m[1].uppercased())⟧" : " \(m[1].uppercased()) "
        }

        // Purple Strong spans used by many modern modules (style="color:#804DB3"):
        //   <span style="color:#804DB3;">H3068</span>
        //   <span style="color:#804DB3;"><sup>7225</sup></span>
        s = replace(
            s,
            pattern: #"(?is)<span[^>]*(?:color\s*[:=]\s*["']?#?(?:804DB3|800080|4B0082|6A0DAD)|#804DB3)[^>]*>\s*(?:<sup[^>]*>)?\s*([HG]?\d{1,5})\s*(?:</sup>)?\s*</span>"#
        ) { m in
            let rawCode = m[1].uppercased()
            if keepMarkers, rawCode.first == "H" || rawCode.first == "G" {
                return "⟦STRONG:\(rawCode)⟧"
            }
            return " \(rawCode) "
        }

        // Bare <sup>H3068</sup> / <sup>G26</sup>
        s = replace(s, pattern: #"(?i)<sup[^>]*>\s*([HG]\d{1,5})\s*</sup>"#) { m in
            keepMarkers ? "⟦STRONG:\(m[1].uppercased())⟧" : " \(m[1].uppercased()) "
        }

        // <ref>…</ref>
        s = replace(s, pattern: #"(?i)<ref(?:\s[^>]*)?>(.*?)</ref>"#) { m in
            let inner = stripTags(m[1])
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.isEmpty { return "" }
            return keepMarkers ? "⟦REF:\(inner)⟧" : " \(inner) "
        }

        // Words of Christ — global:
        //  • <red>…</red>
        //  • <font color=red|#B34D4D|…>
        //  • <span style="color:#B34D4D;">…</span>  (e-Sword Red Letter editions)
        if keepMarkers {
            // Complete red-letter spans first (most Red Letter .bbli modules)
            s = replace(s, pattern: #"(?is)<span\b([^>]*)>(.*?)</span>"#) { m in
                if spanAttributesLookLikeWOC(m[1]) {
                    return "⟦WOC⟧\(m[2])⟦/WOC⟧"
                }
                return m[0]
            }
            s = replace(s, pattern: #"(?is)<red(?:\s[^>]*)?>(.*?)</red>"#) { m in
                "⟦WOC⟧\(m[1])⟦/WOC⟧"
            }
            // Complete <font color=…>…</font> pairs (legacy modules)
            s = replace(s, pattern: #"(?is)<font\b([^>]*)>(.*?)</font>"#) { m in
                if spanAttributesLookLikeWOC(m[1]) {
                    return "⟦WOC⟧\(m[2])⟦/WOC⟧"
                }
                return m[0]
            }
            s = replace(s, pattern: #"(?i)<blu>"#) { _ in "⟦BLU⟧" }
            s = replace(s, pattern: #"(?i)</blu>"#) { _ in "⟦/BLU⟧" }
            // Content form used by some interlinears: already handled as open/close above.
            // Also capture <blu>inner</blu> as BLU:inner for tokenizer word extraction.
            s = replace(s, pattern: #"⟦BLU⟧(.*?)⟦/BLU⟧"#) { m in
                let inner = stripTags(m[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return inner.isEmpty ? "" : "⟦BLU:\(inner)⟧"
            }
        } else {
            // Plain path: unwrap blu/red spans, keep text
            s = replace(s, pattern: #"(?i)</?red(?:\s[^>]*)?>"#) { _ in " " }
            s = replace(s, pattern: #"(?i)</?blu>"#) { _ in " " }
            // Still unwrap red-letter spans so plain text is complete (color dropped)
            s = replace(s, pattern: #"(?is)<span\b([^>]*)>(.*?)</span>"#) { m in
                spanAttributesLookLikeWOC(m[1]) ? " \(m[2]) " : m[0]
            }
        }

        // Unwrap language tags — KEEP their text (lexicons / Hebrew OT / Greek NT).
        // Never delete <grk>…</grk> or <heb>…</heb> content (Mac does not either).
        s = replace(s, pattern: #"(?is)<(?:grk|heb|lat|ara|syr|gra)(?:\s[^>]*)?>(.*?)</(?:grk|heb|lat|ara|syr|gra)>"#) { m in
            " \(m[1]) "
        }

        // Structural breaks → newlines (before entity decode / tag strip)
        s = replace(s, pattern: #"(?i)<br\s*/?>"#) { _ in "\n" }
        s = replace(s, pattern: #"(?i)</?p(?:\s[^>]*)?>"#) { _ in "\n" }
        s = replace(s, pattern: #"(?i)</?div(?:\s[^>]*)?>"#) { _ in "\n" }
        s = replace(s, pattern: #"(?i)</?li(?:\s[^>]*)?>"#) { _ in "\n" }
        s = replace(s, pattern: #"(?i)</?tr(?:\s[^>]*)?>"#) { _ in "\n" }
        s = replace(s, pattern: #"(?i)</?h[1-6](?:\s[^>]*)?>"#) { _ in "\n" }
        s = replace(s, pattern: #"(?i)</?td(?:\s[^>]*)?>"#) { _ in " " }
        s = replace(s, pattern: #"(?i)</?th(?:\s[^>]*)?>"#) { _ in " " }

        // Full HTML entity decode (numeric + complete named set)
        // Same role as Mac `html_escape::decode_html_entities` / mobile textarea.innerHTML
        s = decodeAllHTMLEntities(s)

        // Strip all remaining tags (content already preserved)
        s = stripTags(s)

        // Entities that were inside attributes of broken tags — second pass
        s = decodeAllHTMLEntities(s)

        // Gén_25:16 → Gén 25:16
        s = replace(s, pattern: #"\b([A-Za-záéíóúÁÉÍÓÚñÑ\.]+)_(\d+:\d+(?:-\d+)?)"#) { m in
            "\(m[1]) \(m[2])"
        }

        s = collapseWhitespace(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML entities (complete)

    /// Decode `&#…;`, `&#x…;`, and **all** named HTML entities (`&aacute;` → á).
    /// Also combines UTF-16 surrogate pairs written as two numeric entities
    /// (seen in some e-Sword modules: `&#xDB40;&#xDC6A;`).
    static func decodeAllHTMLEntities(_ input: String) -> String {
        var s = input

        // Numeric first (Hebrew/Greek codepoints + Spanish)
        s = replace(s, pattern: #"&#(x?[0-9a-fA-F]+);"#) { m in
            let body = m[1]
            let value: UInt32?
            if body.lowercased().hasPrefix("x") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body)
            }
            guard let value else { return m[0] }
            // Leave surrogates as private markers so a second pass can pair them
            if value >= 0xD800 && value <= 0xDFFF {
                return String(format: "\u{FFFE}%04X", value) // temporary placeholder
            }
            guard let scalar = UnicodeScalar(value) else { return m[0] }
            return String(Character(scalar))
        }

        // Pair surrogate placeholders produced above
        s = replace(s, pattern: #"\u{FFFE}([Dd][89ABab][0-9A-Fa-f]{2})\u{FFFE}([Dd][C-Fc-f][0-9A-Fa-f]{2})"#) { m in
            guard let hi = UInt32(m[1], radix: 16), let lo = UInt32(m[2], radix: 16) else {
                return ""
            }
            let code = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
            guard let scalar = UnicodeScalar(code) else { return "" }
            return String(Character(scalar))
        }
        // Drop unpaired surrogate placeholders
        s = replace(s, pattern: #"\u{FFFE}[0-9A-Fa-f]{4}"#) { _ in "" }

        // Named — full HTML5 map (Python html.entities.name2codepoint + html5)
        s = replace(s, pattern: #"&([a-zA-Z][a-zA-Z0-9]+);"#) { m in
            let name = m[1]
            if let ch = HTMLNamedEntities.map[name] { return ch }
            // HTML entity names are case-sensitive for some; try exact then as-is variants
            if let ch = HTMLNamedEntities.map[name.lowercased()] { return ch }
            return m[0]
        }
        return s
    }

    // MARK: - RTF (legacy e-Sword — Windows-1252 like Mac)

    private static func rtfToText(_ rtf: String) -> String {
        var s = rtf
        // \'e1 → Windows-1252 / CP1252 (NOT raw Latin-1 for 0x80–0x9F)
        s = replace(s, pattern: #"\\'([0-9a-fA-F]{2})"#) { m in
            guard let byte = UInt8(m[1], radix: 16) else { return "" }
            return windows1252Byte(byte)
        }
        // \u1234? Unicode
        s = replace(s, pattern: #"\\u(-?\d+)\??"#) { m in
            guard var n = Int(m[1]) else { return "" }
            if n < 0 { n += 65536 }
            guard n >= 0, let scalar = UnicodeScalar(n) else { return "" }
            return String(Character(scalar))
        }
        // RTF control words
        s = replace(s, pattern: #"\\[a-zA-Z]+(-?\d+)?[ ]?"#) { _ in " " }
        s = s.replacingOccurrences(of: "{", with: " ")
        s = s.replacingOccurrences(of: "}", with: " ")
        s = s.replacingOccurrences(of: "\\", with: "")
        return stripNulls(s)
    }

    /// Decode one Windows-1252 byte (matches Mac `encoding_rs::WINDOWS_1252`).
    private static func windows1252Byte(_ byte: UInt8) -> String {
        if let s = String(data: Data([byte]), encoding: .windowsCP1252), !s.isEmpty {
            return s
        }
        // Fallback: Latin-1 1:1
        return String(Character(UnicodeScalar(UInt32(byte))!))
    }

    // MARK: - Helpers

    private static func stripTags(_ s: String) -> String {
        replace(s, pattern: #"<[^>]+>"#) { _ in " " }
    }

    private static func stripNulls(_ s: String) -> String {
        if !s.unicodeScalars.contains(where: { $0.value == 0 }) { return s }
        return String(s.unicodeScalars.filter { $0.value != 0 }.map { Character($0) })
    }

    private static func collapseWhitespace(_ s: String) -> String {
        var t = s
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        t = replace(t, pattern: #"[ \t\f\v]+"#) { _ in " " }
        t = replace(t, pattern: #" *\n *"#) { _ in "\n" }
        t = replace(t, pattern: #"\n{3,}"#) { _ in "\n\n" }
        return t
    }

    private static func replace(
        _ input: String,
        pattern: String,
        handler: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let nsRange = NSRange(input.startIndex..., in: input)
        var result = ""
        var last = input.startIndex
        regex.enumerateMatches(in: input, options: [], range: nsRange) { match, _, _ in
            guard let match, let full = Range(match.range, in: input) else { return }
            result += input[last..<full.lowerBound]
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: input) {
                    groups.append(String(input[r]))
                } else {
                    groups.append("")
                }
            }
            result += handler(groups)
            last = full.upperBound
        }
        result += input[last...]
        return result
    }

    /// Extract color from `style="color:…"` or `color="…"` attributes.
    private static func spanAttributesLookLikeWOC(_ attrs: String) -> Bool {
        // style="color:#B34D4D" / color:#B34D4D / color = "red"
        if let re = try? NSRegularExpression(
            pattern: #"(?i)(?:^|[;\s"'])color\s*[:=]\s*["']?#?([0-9a-fA-F]{3,8}|[a-z]+)"#,
            options: []
        ) {
            let ns = NSRange(attrs.startIndex..., in: attrs)
            if let match = re.firstMatch(in: attrs, options: [], range: ns),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: attrs) {
                return isWordsOfChristColor(String(attrs[r]))
            }
        }
        return false
    }
}

/// One contiguous chunk of Bible reading text (Words of Christ flagged).
struct BibleTextRun: Hashable, Sendable {
    let text: String
    let isWordsOfChrist: Bool
}
