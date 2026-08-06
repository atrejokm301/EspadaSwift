import Foundation

enum VerseTokenizer {
    /// Tokenize e-Sword scripture for tappable Spanish words + Strong chips.
    static func tokenize(rawScripture: String, verse: Int) -> [VerseToken] {
        let marked = ESwordText.cleanToMarkers(rawScripture)
        guard !marked.isEmpty else { return [] }

        // Prefer Spanish-first stream when interlinear blu markers exist.
        let hasBlu = marked.contains("⟦BLU:")
        let stream = hasBlu ? interlinearFocused(marked) : marked

        var draft: [MutableToken] = []
        var inWOC = false
        var i = stream.startIndex

        while i < stream.endIndex {
            if stream[i...].hasPrefix("⟦WOC⟧") {
                inWOC = true
                i = stream.index(i, offsetBy: 5)
                continue
            }
            if stream[i...].hasPrefix("⟦/WOC⟧") {
                inWOC = false
                i = stream.index(i, offsetBy: 6)
                continue
            }
            if stream[i...].hasPrefix("⟦STRONG:") {
                if let end = stream[i...].range(of: "⟧") {
                    let inner = stream[stream.index(i, offsetBy: 8)..<end.lowerBound]
                    let code = String(inner).uppercased()
                    draft.append(.init(kind: .strong, text: code, woc: inWOC, blu: false))
                    i = end.upperBound
                    continue
                }
            }
            if stream[i...].hasPrefix("⟦BLU:") {
                if let end = stream[i...].range(of: "⟧") {
                    let inner = stream[stream.index(i, offsetBy: 5)..<end.lowerBound]
                    appendWords(String(inner), woc: inWOC, blu: true, into: &draft)
                    i = end.upperBound
                    continue
                }
            }

            let ch = stream[i]
            if ch.isWhitespace {
                var j = i
                while j < stream.endIndex && stream[j].isWhitespace {
                    j = stream.index(after: j)
                }
                draft.append(.init(kind: .whitespace, text: " ", woc: inWOC, blu: false))
                i = j
                continue
            }

            if ch.isLetter || ch == "'" || ch == "’" || ch == "ʻ" {
                var j = i
                while j < stream.endIndex {
                    let c = stream[j]
                    if c.isLetter || c.isNumber || c == "'" || c == "’" || c == "ʻ" || c == "-" {
                        j = stream.index(after: j)
                    } else {
                        break
                    }
                }
                let word = String(stream[i..<j])
                if StrongNormalizer.looksLikeStrong(word) {
                    draft.append(.init(kind: .strong, text: word.uppercased(), woc: inWOC, blu: false))
                } else {
                    draft.append(.init(kind: .word, text: word, woc: inWOC, blu: false))
                }
                i = j
                continue
            }

            // punctuation / other
            draft.append(.init(kind: .punctuation, text: String(ch), woc: inWOC, blu: false))
            i = stream.index(after: i)
        }

        linkStrongs(&draft)

        // Drop e-Sword morphology leftovers (VqAmSM3, vaw3ms, NPDSMN, …) — never Spanish.
        draft = draft.filter { tok in
            if tok.kind == .word || tok.kind == .other {
                if StrongResolve.isMorphologyCode(tok.text) { return false }
            }
            return true
        }

        return draft.enumerated().map { idx, t in
            VerseToken(
                kind: t.kind,
                text: t.text,
                strongCodes: t.linkedStrongs,
                isWordsOfChrist: t.woc,
                isInterlinearSpanish: t.blu,
                idSuffix: "\(verse)-\(idx)"
            )
        }
    }

    // MARK: - Private

    private struct MutableToken {
        var kind: TokenKind
        var text: String
        var woc: Bool
        var blu: Bool
        var linkedStrongs: [String] = []
    }

    /// Keep Spanish (blu) + Strong markers; drop most Greek/translit noise already partially cleaned.
    private static func interlinearFocused(_ marked: String) -> String {
        // Keep STRONG, BLU, WOC markers and punctuation between them; strip long latin translit runs without blu.
        // After cleanToMarkers, Greek tags are gone; leftover is often "gar Houtô" etc.
        // Strategy: only emit BLU contents, STRONG markers, WOC, and light punctuation from original order via regex scan.
        var out = ""
        var i = marked.startIndex
        while i < marked.endIndex {
            if marked[i...].hasPrefix("⟦") {
                if let end = marked[i...].range(of: "⟧") {
                    out += marked[i..<end.upperBound]
                    i = end.upperBound
                    continue
                }
            }
            // keep simple punctuation and spaces
            let ch = marked[i]
            if ch.isWhitespace || ".,;:!?«»\"'()[]—–-".contains(ch) {
                out.append(ch)
            }
            // drop bare latin/greek letters outside markers (transliteration)
            i = marked.index(after: i)
        }
        return out
    }

    private static func appendWords(_ text: String, woc: Bool, blu: Bool, into draft: inout [MutableToken]) {
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch.isWhitespace {
                draft.append(.init(kind: .whitespace, text: " ", woc: woc, blu: blu))
                i = text.index(after: i)
                continue
            }
            if ch.isLetter || ch == "'" || ch == "’" {
                var j = i
                while j < text.endIndex {
                    let c = text[j]
                    if c.isLetter || c.isNumber || c == "'" || c == "’" || c == "-" {
                        j = text.index(after: j)
                    } else { break }
                }
                draft.append(.init(kind: .word, text: String(text[i..<j]), woc: woc, blu: blu))
                i = j
                continue
            }
            draft.append(.init(kind: .punctuation, text: String(ch), woc: woc, blu: blu))
            i = text.index(after: i)
        }
    }

    /// Attach nearby Strong codes to Spanish words.
    /// - RV1960+ (con Strong): Spanish **then** Strong → look forward first
    /// - iRV reverse interlinear: Strong **then** Spanish blu → look backward
    private static func linkStrongs(_ draft: inout [MutableToken]) {
        let n = draft.count
        for i in 0..<n {
            guard draft[i].kind == .word else { continue }
            var codes: [String] = []

            // Forward first: `Deléitate <num>H6026</num>` (RV1960+)
            var f = i + 1
            var steps = 0
            while f < n && steps < 6 {
                if draft[f].kind == .whitespace { f += 1; continue }
                if draft[f].kind == .strong {
                    codes.append(draft[f].text)
                    break
                }
                // Skip morphology crumbs between word and Strong
                if draft[f].kind == .word, StrongResolve.isMorphologyCode(draft[f].text) {
                    f += 1
                    steps += 1
                    continue
                }
                if draft[f].kind == .word { break }
                f += 1
                steps += 1
            }

            // Backward: reverse interlinear Strong before blu Spanish
            if codes.isEmpty {
                var b = i - 1
                steps = 0
                while b >= 0 && steps < 6 {
                    if draft[b].kind == .whitespace { b -= 1; continue }
                    if draft[b].kind == .strong {
                        codes.append(draft[b].text)
                        break
                    }
                    if draft[b].kind == .word { break }
                    b -= 1
                    steps += 1
                }
            }

            draft[i].linkedStrongs = codes
        }
    }
}
