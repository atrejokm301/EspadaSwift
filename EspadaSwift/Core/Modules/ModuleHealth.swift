import Foundation

/// Encoding health of one module, measured from a sample at catalog time.
///
/// Purpose is to tell the reader *why* a module looks wrong, and to let the store prefer
/// a clean copy when the same work is installed twice (the library on disk has both a
/// clean and a corrupted Chávez, and two identical Vila Escuain copies).
struct ModuleHealth: Codable, Hashable, Sendable {

    enum Severity: String, Codable, Sendable {
        /// Nothing detected.
        case clean
        /// Visible but rare — a handful of characters across the module.
        case minor
        /// Pervasive; the module is hard to read as-is.
        case damaged
    }

    /// Isolated non-Latin letters wedged inside Latin words (legacy codepage damage).
    /// Only repaired when `ModuleTextRepair.repairsCodepageWedges` is enabled.
    var wedgeHits: Int = 0
    /// Private-use glyphs with no known meaning — these still render as empty boxes.
    var unmappedPrivateUseHits: Int = 0
    /// Hebrew/Greek that was mangled into Latin. Never repairable one-way, so it always
    /// counts against the module however the repair settings are configured.
    var mangledScriptRuns: Int = 0
    /// Rows carrying a UTF-8-read-as-Latin-1 signature. Repaired automatically.
    var mojibakeRows: Int = 0
    /// Publisher-font glyphs Espada knows how to expand. Repaired automatically.
    var repairedPrivateUseHits: Int = 0
    /// Rows examined to produce the counts above.
    var sampledRows: Int = 0

    var isClean: Bool { severity == .clean }

    /// Damage the reader would still see, given what the pipeline repairs today.
    /// Reina 1569's `ct` ligature is common but fully handled, so it is not counted —
    /// warning about text that now renders correctly would just be noise.
    var residualHits: Int {
        var total = unmappedPrivateUseHits + mangledScriptRuns
        if !ModuleTextRepair.repairsCodepageWedges { total += wedgeHits }
        return total
    }

    /// Residual damage per sampled row — comparable across modules of very different sizes.
    var hitsPerRow: Double {
        guard sampledRows > 0 else { return 0 }
        return Double(residualHits) / Double(sampledRows)
    }

    var severity: Severity {
        if residualHits == 0 { return .clean }
        // Swanson runs ~1.3 wedges per row; Vila Escuain has a single hit in 2 894 rows.
        return hitsPerRow >= 0.05 ? .damaged : .minor
    }

    /// Short Spanish explanation for the Módulos list. `nil` when nothing is left to warn about.
    var spanishSummary: String? {
        switch severity {
        case .clean:
            return nil
        case .minor:
            return "Algunos caracteres dañados en este módulo."
        case .damaged:
            if mangledScriptRuns > 0 {
                return "Codificación dañada: el hebreo/griego de este módulo se guardó como letras latinas."
            }
            if wedgeHits > unmappedPrivateUseHits {
                return "Codificación dañada: acentos guardados como letras griegas o hebreas."
            }
            return "Usa una fuente propia; algunos caracteres no se ven en iOS."
        }
    }

    /// Measure one field and fold it into the running totals.
    mutating func accumulate(sample: String) {
        sampledRows += 1
        wedgeHits += ModuleTextRepair.countCodepageWedges(sample)
        mangledScriptRuns += ModuleTextRepair.countMangledScriptRuns(sample)
        if ModuleTextRepair.hasMojibakeSignature(sample) { mojibakeRows += 1 }
        for scalar in sample.unicodeScalars where scalar.value >= 0xE000 && scalar.value <= 0xF8FF {
            if ModuleTextRepair.canExpandPrivateUse(scalar) {
                repairedPrivateUseHits += 1
            } else {
                unmappedPrivateUseHits += 1
            }
        }
    }
}

extension ModuleInfo {
    /// Significant words of the title, for spotting the same work installed twice.
    ///
    /// Exact matching is not enough — the library holds two copies of Chávez titled
    /// *"Diccionario de Hebreo Bíblico por Moisés Chávez"* and
    /// *"Diccionario De Hebreo Biblico --MOISES CHAVEZ"*, and two Tuggys that differ the
    /// same way. Dropping accents, case, punctuation and connecting words makes both
    /// pairs line up exactly.
    var titleTokens: Set<String> {
        let base = title.isEmpty ? filename : title
        let folded = base
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        // Short words are connectives ("de", "por", "del", "nt") or ordering prefixes.
        return Set(words.map(String.init).filter { $0.count > 2 && !Self.titleStopwords.contains($0) })
    }

    private static let titleStopwords: Set<String> = [
        "por", "con", "del", "las", "los", "una", "the", "and", "for", "his",
        "modulo", "module", "esword", "version", "biblico", "biblia",
    ]

    /// Same work? Requires the same kind and near-identical significant words.
    func isSameWork(as other: ModuleInfo) -> Bool {
        guard kind == other.kind else { return false }
        let a = titleTokens
        let b = other.titleTokens
        guard a.count >= 3, b.count >= 3 else { return false }
        let shared = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return false }
        return Double(shared) / Double(union) >= 0.75
    }

    /// Lower is better. Unknown health sits between clean and damaged so an unsampled
    /// module is never demoted below one we know is broken.
    var healthRank: Int {
        switch health?.severity {
        case .clean: return 0
        case .none: return 1
        case .minor: return 2
        case .damaged: return 3
        }
    }
}
