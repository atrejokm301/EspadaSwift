import Foundation

/// Repairs characters that are damaged in the module file itself, as opposed to
/// notation the publisher meant to be there (that is `ESwordText`'s job).
///
/// Findings come from a full audit of the 130-module library on disk
/// (1.66 M rows / 580 M characters). 109 modules are completely clean; the damage is
/// concentrated and each kind decodes deterministically:
///
/// | Kind | Where | Example |
/// |------|-------|---------|
/// | private-use ligature | Reina 1569, Biblia del Oso, RV1602 | `ſan\u{E003}ificólo` → `ſanctificólo` |
/// | private-use letter | Chávez (broken copy), Keil-Delitzsch | `ling\u{F895}ística` → `lingüística` |
/// | UTF-8 read as Latin-1 | Biblia Latinoamérica 1995 | `1CrÃ³n` → `1Crón` |
/// | codepage wedge | Swanson, Tuggy, Multiléxico, Pikaza | `tambiιn` → `también` |
///
/// **Deliberately not touched** — these look wrong but are correct content:
/// Harrison's Cyrillic schwa `ә` in `bәliyyaʿal` (phonetic transliteration), PSH2015's
/// Syriac letters (Psalm 119 acrostic markers), BTX4's Arabic (a gematria discussion).
/// That is why nothing here filters "unexpected" scripts wholesale.
enum ModuleTextRepair {

    // MARK: - Feature flag

    /// Codepage-wedge repair.
    ///
    /// On by default: it is the single largest source of garbled text in the library
    /// (Swanson alone has ~7 300 damaged characters) and, unlike the duplicate-preference
    /// rule, nothing else can help those modules — Swanson, Tuggy, Pikaza and Keil have no
    /// clean copy installed. The transform is deterministic and adjacency-guarded, so real
    /// Hebrew and Greek cannot be touched (see `repairCodepageWedges`).
    ///
    /// Set to `false` to turn it off; the value is read at catalog-scan time too, so
    /// `ModuleHealth.severity` reports wedge damage again when disabled.
    nonisolated(unsafe) static var repairsCodepageWedges = true

    // MARK: - Entry point

    /// Full repair pass. Cheap no-op for the 109 clean modules — one scalar scan decides.
    static func sanitize(_ input: String) -> String {
        guard needsRepair(input) else { return input }
        var s = expandPrivateUseCharacters(input)
        s = repairMojibake(s)
        if repairsCodepageWedges {
            s = repairCodepageWedges(s)
        }
        s = dropUnusableCharacters(s)
        return s
    }

    /// Single pass deciding whether any repair could apply. Keeps the common case free.
    static func needsRepair(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v < 0x80 { continue }
            // C1 controls, replacement char, private use, mojibake lead bytes
            if (v >= 0x80 && v <= 0x9F) || v == 0xFFFD { return true }
            if (v >= 0xE000 && v <= 0xF8FF) { return true }
            if v == 0x00C2 || v == 0x00C3 || v == 0x00E2 { return true }
            if repairsCodepageWedges, isRemappableScalar(scalar) { return true }
        }
        return false
    }

    // MARK: - Private-use characters

    /// Glyphs from the publisher's custom font. They carry real text but render as empty
    /// boxes on iOS, which is what makes 16th-century Reina editions look broken.
    ///
    /// `U+E000` is an abbreviation glyph for *que*, so it needs a following space when the
    /// next character is a letter: `por\u{E000}es` is "porque es", not "porquees".
    private static let privateUseText: [UnicodeScalar: String] = [
        "\u{E000}": "que",   // que-abbreviation (RV1602)
        "\u{E003}": "ct",    // ct-ligature (Reina 1569 / Biblia del Oso / RV1602)
        "\u{F895}": "ü",     // u-diaeresis (broken Chávez, Keil-Delitzsch)
    ]

    /// True when this private-use glyph has a known expansion, so health scoring can tell
    /// "handled by the pipeline" apart from "still renders as a box".
    static func canExpandPrivateUse(_ scalar: UnicodeScalar) -> Bool {
        privateUseText[scalar] != nil
    }

    static func expandPrivateUseCharacters(_ input: String) -> String {
        guard input.unicodeScalars.contains(where: { $0.value >= 0xE000 && $0.value <= 0xF8FF }) else {
            return input
        }
        var out = ""
        out.reserveCapacity(input.count + 8)
        var pendingSpacer = false

        for ch in input {
            if pendingSpacer {
                pendingSpacer = false
                if ch.isLetter { out.append(" ") }
            }
            guard let scalar = ch.unicodeScalars.first,
                  ch.unicodeScalars.count == 1,
                  scalar.value >= 0xE000, scalar.value <= 0xF8FF else {
                out.append(ch)
                continue
            }
            if let text = privateUseText[scalar] {
                out.append(text)
                // Word-abbreviation glyphs need a boundary; letter substitutions do not.
                pendingSpacer = text.count > 2
            }
            // Unmapped private use renders as tofu — drop rather than show a box.
        }
        return out
    }

    // MARK: - Mojibake (UTF-8 decoded as Latin-1)

    /// `1CrÃ³n` → `1Crón`. Repairs only the matched byte pairs, never the whole string:
    /// affected rows mix correct text with damaged text, so a whole-string round-trip
    /// would fail (or worse, half-succeed) on the correct half.
    static func repairMojibake(_ input: String) -> String {
        guard input.contains("Ã") || input.contains("Â") || input.contains("â") else {
            return input
        }
        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0

        while i < chars.count {
            // A mis-decoded UTF-8 sequence always begins with one of these lead bytes.
            let lead = chars[i]
            let width: Int
            switch lead {
            case "Ã", "Â": width = 2   // 2-byte sequence: accented Latin, ¡, ¿, …
            case "â":      width = 3   // 3-byte sequence: “ ” ‘ ’ – — €
            default:
                out.append(lead)
                i += 1
                continue
            }
            guard i + width <= chars.count,
                  let decoded = decodeAsUTF8Bytes(chars[i..<(i + width)]) else {
                out.append(lead)
                i += 1
                continue
            }
            out.append(decoded)
            i += width
        }
        return out
    }

    /// Re-encode characters through Windows-1252 to recover the original bytes, then read
    /// them as UTF-8. Going through CP1252 rather than raw scalar values is what makes the
    /// 3-byte punctuation forms work: `â€™` is `E2 80 99`, but `€` is U+20AC, not U+0080.
    private static func decodeAsUTF8Bytes(_ slice: ArraySlice<Character>) -> Character? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(slice.count)
        for ch in slice {
            if let data = String(ch).data(using: .windowsCP1252), data.count == 1 {
                bytes.append(data[0])
                continue
            }
            // CP1252 leaves 0x81/0x8D/0x8F/0x90/0x9D undefined, so a decoder that fell back
            // to Latin-1 for those emits the raw value. `”` (E2 80 9D) lands here.
            guard let scalar = ch.unicodeScalars.first,
                  ch.unicodeScalars.count == 1,
                  scalar.value <= 0xFF else { return nil }
            bytes.append(UInt8(scalar.value))
        }
        guard let decoded = String(bytes: bytes, encoding: .utf8),
              decoded.count == 1,
              let ch = decoded.first,
              // A successful repair always yields a non-ASCII character; anything else
              // means we matched a coincidence rather than real damage.
              !ch.isASCII else { return nil }
        return ch
    }

    // MARK: - Codepage wedges

    /// Some modules were authored as Windows-1252 Spanish but written out through the
    /// Greek (CP1253) or Hebrew (CP1255) table, so every accented letter became a Greek
    /// or Hebrew letter *at the same byte value*. Mapping each one back through its own
    /// codepage and re-reading it as CP1252 restores the original exactly:
    ///
    /// ```
    /// tambiιn → también      espaρol → español      Mσdulo → Módulo
    /// agapaτ  → agapaô       Sφhne   → Söhne        informaciףn → información
    /// ```
    ///
    /// Safety rests on adjacency, not on the character alone: only an **isolated**
    /// non-Latin letter touching a Latin letter is rewritten. Genuine Hebrew and Greek in
    /// these modules always appears in runs of two or more, separated from Latin text, so
    /// a real lemma such as `ἀγάπη` or `לֵב` can never be altered.
    ///
    /// This does **not** rescue the broken Chávez copy: there the damage runs both ways
    /// (its Spanish became Hebrew *and* its Hebrew became Latin), which is why that module
    /// is flagged so the clean copy is preferred instead.
    static func repairCodepageWedges(_ input: String) -> String {
        guard input.unicodeScalars.contains(where: isRemappableScalar) else { return input }

        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count)

        for i in chars.indices {
            let ch = chars[i]
            guard ch.unicodeScalars.count == 1,
                  let scalar = ch.unicodeScalars.first,
                  let replacement = remapTable[scalar] else {
                out.append(ch)
                continue
            }
            // Isolated? A neighbouring non-Latin letter means this is genuine script.
            let prev = i > chars.startIndex ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if let prev, isNonLatinLetter(prev) { out.append(ch); continue }
            if let next, isNonLatinLetter(next) { out.append(ch); continue }
            // Touching Latin text on at least one side ⇒ corrupt.
            let touchesLatin = isLatinLetter(prev) || isLatinLetter(next)
            out.append(touchesLatin ? replacement : ch)
        }
        return out
    }

    /// How many isolated non-Latin letters sit inside Latin words. Used for health scoring;
    /// stricter than the repair rule (both sides must be Latin) so the score never inflates.
    static func countCodepageWedges(_ input: String) -> Int {
        guard input.unicodeScalars.contains(where: isRemappableScalar) else { return 0 }
        let chars = Array(input)
        var count = 0
        for i in chars.indices where i > 0 && i + 1 < chars.count {
            guard chars[i].unicodeScalars.count == 1,
                  let scalar = chars[i].unicodeScalars.first,
                  remapTable[scalar] != nil else { continue }
            if isLatinLetter(chars[i - 1]) && isLatinLetter(chars[i + 1]) {
                count += 1
            }
        }
        return count
    }

    /// Runs of original script that were mangled *into* Latin — the opposite direction to
    /// `countCodepageWedges`, and not repairable one-way.
    ///
    /// The broken Chávez lost its Spanish accents to Hebrew **and** its Hebrew to Latin
    /// (`àÆáÀéåéï` is a Hebrew word read through CP1252). Four or more consecutive
    /// non-ASCII Latin letters is the fingerprint: real Spanish never stacks them —
    /// `niño` and `Génesis` have one apiece. Across the 130-module library this fires on
    /// exactly three files, all genuinely damaged.
    ///
    /// Counting this is what keeps the damaged Chávez ranked below its clean twin even
    /// when wedge repair has already fixed its Spanish.
    static func countMangledScriptRuns(_ input: String) -> Int {
        var count = 0
        var run = 0
        for ch in input {
            if isHighLatinLetter(ch) {
                run += 1
                if run == 4 { count += 1 }
            } else {
                run = 0
            }
        }
        return count
    }

    /// Latin-1 Supplement / Latin Extended-A letter (à, Æ, é, ï, ā …) — never plain ASCII.
    private static func isHighLatinLetter(_ ch: Character) -> Bool {
        guard ch.isLetter, ch.unicodeScalars.count == 1, let scalar = ch.unicodeScalars.first else {
            return false
        }
        return scalar.value >= 0x00C0 && scalar.value <= 0x024F
    }

    static func hasMojibakeSignature(_ input: String) -> Bool {
        guard input.contains("Ã") || input.contains("Â") || input.contains("â") else { return false }
        return repairMojibake(input) != input
    }

    // MARK: - Unusable characters

    /// C1 controls and replacement characters survive some legacy conversions and render
    /// as nothing or as `�`. Unmapped private use is handled in the expansion pass.
    static func dropUnusableCharacters(_ input: String) -> String {
        guard input.unicodeScalars.contains(where: {
            ($0.value >= 0x80 && $0.value <= 0x9F) || $0.value == 0xFFFD
        }) else { return input }
        var scalars = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            let v = scalar.value
            if (v >= 0x80 && v <= 0x9F) || v == 0xFFFD { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    // MARK: - Tables

    /// Greek (CP1253) and Hebrew (CP1255) scalars → the Windows-1252 letter that shares
    /// their byte. Built once from the system encodings rather than hand-typed.
    private static let remapTable: [UnicodeScalar: Character] = {
        var map: [UnicodeScalar: Character] = [:]

        func latin(_ byte: UInt8) -> Character? {
            guard let s = String(data: Data([byte]), encoding: .windowsCP1252),
                  let c = s.first, c.isLetter else { return nil }
            return c
        }

        // Greek: read the real CP1253 table so no byte is guessed.
        for byte in UInt8(0x80)...UInt8(0xFF) {
            guard let src = String(data: Data([byte]), encoding: .windowsCP1253),
                  let scalar = src.unicodeScalars.first,
                  scalar.value >= 0x0370, scalar.value <= 0x03FF,
                  let dst = latin(byte) else { continue }
            map[scalar] = dst
        }

        // Hebrew: CP1255 is not exposed by Foundation, but its letter block is linear —
        // bytes 0xE0…0xFA map to U+05D0…U+05EA.
        for offset in 0...(0xFA - 0xE0) {
            let byte = UInt8(0xE0 + offset)
            guard let scalar = UnicodeScalar(0x05D0 + UInt32(offset)),
                  let dst = latin(byte) else { continue }
            map[scalar] = dst
        }
        return map
    }()

    private static func isRemappableScalar(_ scalar: UnicodeScalar) -> Bool {
        remapTable[scalar] != nil
    }

    private static func isLatinLetter(_ ch: Character?) -> Bool {
        guard let ch, ch.isLetter else { return false }
        return ch.unicodeScalars.allSatisfy { $0.value < 0x0370 }
    }

    private static func isNonLatinLetter(_ ch: Character) -> Bool {
        guard ch.isLetter else { return false }
        return ch.unicodeScalars.contains { $0.value >= 0x0370 }
    }
}
