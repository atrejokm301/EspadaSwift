import Foundation
import Observation
import SwiftUI

/// Shared study state: location + word/Strong selection drives all four resource tabs.
@Observable
final class StudySession {
    // Location
    var book: Int = 43
    var chapter: Int = 3
    var verse: Int = 16

    // Selection
    var selectedWord: String?
    var strongCode: String?
    /// Hits from interlinear Strong’s resolve (Greek/Hebrew + translit).
    var strongHits: [StrongHit] = []
    /// User-facing note when resolve fails or needs an interlinear module.
    var strongResolveNote: String?
    /// True while background interlinear resolve is in flight.
    var isResolvingStrongs = false
    /// Léxico search-field text (Windows parity).
    /// **Always a Strong code (H/G) when known** — never auto-filled with the Spanish surface
    /// form from a verse tap. Spanish belongs on the word card only.
    var lexiconQueryField: String = ""
    var selectionSource: SelectionSource = .navigation

    // Active modules (paths) — one per type
    /// Reading Bible shown in the Biblia tab (prefer plain RV1960 — never forced to iRV).
    var activeBiblePath: String?
    var activeCommentaryPath: String?
    var activeDictionaryPath: String?
    var activeLexiconPath: String?

    /// Silent Strong-map module (e.g. iRV 1960+). Used only as a lookup table for
    /// Spanish word → G/H + Greek/Hebrew while the user **keeps reading** RV1960.
    /// Never opened as the main reading Bible unless the user picks it themselves.
    var activeInterlinearPath: String?
    var interlinearMapLabel: String?

    /// Plain Spanish Bible (RV1960 as-is) when the reading Bible is interlinear.
    /// Used by the **lexicon** tab for clean Spanish context — not dual-Bible UI.
    var companionSpanishBiblePath: String?
    /// verse number → plain Spanish text for the current chapter (from companion)
    var companionVerseSpanish: [Int: String] = [:]
    var companionBibleLabel: String?

    /// Last 10 distinct book/chapter/verse locations (most recent first).
    var recentVerses: [RecentVerse] = []
    /// Active cross-reference module path (TSK-style commentary), separate from study commentary.
    var activeCrossReferencePath: String?
    var crossReferenceEntries: [StudyEntry] = []
    var crossReferenceError: String?
    var isLoadingCrossReferences = false

    // Commentary scopes — verse + chapter on by default so word/verse/chapter study
    // surfaces more of the module (book remains opt-in; can be huge).
    var commentaryVerseScope = true
    var commentaryChapterScope = true
    var commentaryBookScope = false

    // Navigation focus after tap
    var focusedTab: AppTab = .bible
    var focusToken = UUID()
    // Note: focusedTab is mutated from HighlightSheet / word taps

    // Loaded content
    var chapterVerses: [VerseRow] = []
    /// Tokens only for the currently selected verse (performance).
    var selectedVerseTokens: [VerseToken] = []
    var isLoadingChapter = false
    var chapterError: String?

    var dictionaryResults: [DictEntry] = []
    var dictionaryError: String?
    var isLoadingDictionary = false

    var lexiconEntry: DictEntry?
    var lexiconError: String?
    var isLoadingLexicon = false
    var lexiconNeedsStrongsBible = false

    var commentaryEntries: [StudyEntry] = []
    var commentaryError: String?
    var isLoadingCommentary = false

    /// path → has content for current context (dropdown badges)
    var commentaryAvailability: [String: Bool] = [:]
    var dictionaryAvailability: [String: Bool] = [:]
    var lexiconAvailability: [String: Bool] = [:]
    var isProbingAvailability = false

    /// "book:chapter:verse" → HighlightColor.rawValue
    var highlights: [String: String] = [:]

    /// Popup from tapping a Strong / Bible ref inside study text.
    var activePeek: StudyPeek?

    // Module store reference
    weak var store: ModuleStore?

    /// Saved module filenames (stable across re-import / path changes)
    private var savedBibleFile: String?
    private var savedCommentaryFile: String?
    private var savedDictionaryFile: String?
    private var savedLexiconFile: String?
    private var savedCrossReferenceFile: String?
    private var savedInterlinearFile: String?

    /// Cancels in-flight study reloads so rapid taps cannot race.
    private var studyLoadTask: Task<Void, Never>?
    /// Cancels neighbor prefetch when the user jumps again quickly.
    private var prefetchTask: Task<Void, Never>?
    /// Cancels chapter/commentary cascade on rapid navigation or version switch.
    private var navigationTask: Task<Void, Never>?
    /// Debounced green-dot probes (never block reading).
    private var availabilityTask: Task<Void, Never>?
    /// Dedupes concurrent reloads of the same chapter (BibleView.task + setActiveModule).
    private var loadingChapterKey: String?
    private var lastPresentedChapterKey: String?
    /// Dedupes commentary reloads (session nav + CommentaryView.task).
    private var lastCommentaryKey: String?

    /// Per-module last positions / queries (survives module switching).
    private var moduleMemory = ModulePositionMemory.load()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let book = "espada.book"
        static let chapter = "espada.chapter"
        static let verse = "espada.verse"
        static let bible = "espada.bible"
        static let commentary = "espada.commentary"
        static let dictionary = "espada.dictionary"
        static let lexicon = "espada.lexicon"
        static let bibleFile = "espada.bible.filename"
        static let commentaryFile = "espada.commentary.filename"
        static let dictionaryFile = "espada.dictionary.filename"
        static let lexiconFile = "espada.lexicon.filename"
        static let selectedWord = "espada.selectedWord"
        static let strongCode = "espada.strongCode"
        static let highlights = "espada.highlights"
        static let companionSpanish = "espada.companionSpanishBible"
        static let companionSpanishFile = "espada.companionSpanishBible.filename"
        static let interlinear = "espada.interlinearMap"
        static let interlinearFile = "espada.interlinearMap.filename"
        static let recentVerses = "espada.recentVerses"
        static let crossReference = "espada.crossReference"
        static let crossReferenceFile = "espada.crossReference.filename"
        /// One-shot migration: stop forcing iRV as the reading Bible.
        static let migratedPlainReading = "espada.migratedPlainReadingBible.v2"
    }

    private var savedCompanionSpanishFile: String?

    /// Cap for the recent-verses menu (matches Espada Mobile).
    static let recentVersesLimit = 10

    init() {
        book = defaults.object(forKey: Keys.book) as? Int ?? 43
        chapter = defaults.object(forKey: Keys.chapter) as? Int ?? 3
        verse = defaults.object(forKey: Keys.verse) as? Int ?? 16
        activeBiblePath = defaults.string(forKey: Keys.bible)
        activeCommentaryPath = defaults.string(forKey: Keys.commentary)
        activeDictionaryPath = defaults.string(forKey: Keys.dictionary)
        activeLexiconPath = defaults.string(forKey: Keys.lexicon)
        activeCrossReferencePath = defaults.string(forKey: Keys.crossReference)
        savedBibleFile = defaults.string(forKey: Keys.bibleFile)
        savedCommentaryFile = defaults.string(forKey: Keys.commentaryFile)
        savedDictionaryFile = defaults.string(forKey: Keys.dictionaryFile)
        savedLexiconFile = defaults.string(forKey: Keys.lexiconFile)
        savedCrossReferenceFile = defaults.string(forKey: Keys.crossReferenceFile)
        selectedWord = defaults.string(forKey: Keys.selectedWord)
        strongCode = defaults.string(forKey: Keys.strongCode)
        companionSpanishBiblePath = defaults.string(forKey: Keys.companionSpanish)
        savedCompanionSpanishFile = defaults.string(forKey: Keys.companionSpanishFile)
        activeInterlinearPath = defaults.string(forKey: Keys.interlinear)
        savedInterlinearFile = defaults.string(forKey: Keys.interlinearFile)
        if let data = defaults.data(forKey: Keys.highlights),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            highlights = map
        }
        if let data = defaults.data(forKey: Keys.recentVerses),
           let list = try? JSONDecoder().decode([RecentVerse].self, from: data) {
            recentVerses = Array(list.prefix(Self.recentVersesLimit))
        }
        // Seed dictionary/lexicon query memory only (BCV is global, not per-module)
        rememberCurrentDictionaryQuery()
        rememberCurrentLexiconQuery()
        // Seed history with the restored location so the menu is never empty on first open
        trackRecentVerse(book: book, chapter: chapter, verse: verse)
    }

    /// True when a plain Spanish companion is wired for lexicon context (not for dual Bible UI).
    var isCompanionSpanishActive: Bool {
        guard let c = companionSpanishBiblePath, !c.isEmpty else { return false }
        guard let active = activeBiblePath, active != c else { return false }
        return isStudyBible(path: active)
    }

    private func isStudyBible(path: String) -> Bool {
        let name = ((path as NSString).lastPathComponent + path).lowercased()
        return name.contains("interlineal") || name.contains("interlinear")
            || name.contains("irv") || name.contains("strong")
            || name.contains("con_strong") || name.contains("+")
    }

    private func isPlainRV1960(_ mod: ModuleInfo) -> Bool {
        let hay = (mod.title + " " + mod.abbreviation + " " + mod.filename).lowercased()
        let looksRV = hay.contains("rv1960") || hay.contains("rv 1960")
            || (hay.contains("reina") && hay.contains("1960") && hay.contains("valera"))
        let isInter = hay.contains("interlineal") || hay.contains("interlinear") || hay.contains("irv")
        let isStrongHeavy = hay.contains("con_strong") || hay.contains("con strong")
            || hay.contains("with_strong") || hay.contains("+")
        // Plain “as is” RV1960 — not interlinear, not Strong-tagged edition
        return looksRV && !isInter && !isStrongHeavy && !mod.hasStrongs
    }

    private func isInterlinearOrStrongRV(_ mod: ModuleInfo) -> Bool {
        let hay = (mod.title + " " + mod.abbreviation + " " + mod.filename).lowercased()
        if hay.contains("interlineal") || hay.contains("irv") { return true }
        if (hay.contains("rv1960") || hay.contains("1960")) && (mod.hasStrongs || hay.contains("strong")) {
            return true
        }
        return mod.hasStrongs && (hay.contains("strong") || hay.contains("interlineal"))
    }

    // MARK: - Per-module memory

    /// Spanish + Strong + verse context for the lexicon (RV1960 / interlinear).
    var lexiconStudyContext: LexiconStudyContext {
        buildLexiconStudyContext()
    }

    /// Canonical Strong code for the Léxico bar, or nil if not yet resolved.
    var lexiconStrongForSearchBar: String? {
        if let s = strongCode, StrongNormalizer.looksLikeStrong(s) {
            return StrongNormalizer.normalize(s)
        }
        if let hit = strongHits.first(where: { StrongNormalizer.looksLikeStrong($0.strong) }) {
            return StrongNormalizer.normalize(hit.strong)
        }
        if StrongNormalizer.looksLikeStrong(lexiconQueryField) {
            return StrongNormalizer.normalize(lexiconQueryField)
        }
        return nil
    }

    /// Push Strong into the Léxico search field. Never call this with Spanish.
    func setLexiconSearchToStrong(_ code: String) {
        guard let norm = StrongResolve.normalizeStrong(code)
                ?? (StrongNormalizer.looksLikeStrong(code) ? StrongNormalizer.normalize(code) : nil)
        else { return }
        lexiconQueryField = norm
        if strongCode == nil || StrongNormalizer.normalize(strongCode ?? "") != norm {
            strongCode = norm
        }
    }

    var passagePickerTestamentOT: Bool {
        moduleMemory.passagePickerTestament != "nt"
    }

    func rememberPassagePicker(testamentIsOT: Bool, book: Int) {
        moduleMemory.passagePickerTestament = testamentIsOT ? "ot" : "nt"
        moduleMemory.passagePickerBook = book
        moduleMemory.save(to: defaults)
    }

    private func memoryKey(for path: String?) -> String? {
        ModulePositionMemory.fileKey(path: path)
    }

    /// True when the user is mid-study (word and/or Strong). Module switches must NOT
    /// replace this with another module’s old remembered query.
    private var hasActiveStudyFocus: Bool {
        if let s = strongCode, StrongNormalizer.looksLikeStrong(s) { return true }
        if let w = selectedWord, StrongResolve.isPlausibleSpanishGloss(w) { return true }
        if StrongNormalizer.looksLikeStrong(lexiconQueryField) { return true }
        return false
    }

    private func rememberCurrentDictionaryQuery() {
        guard let key = memoryKey(for: activeDictionaryPath),
              let q = selectedWord, !q.isEmpty else { return }
        moduleMemory.dictionaryQueries[key] = .init(query: q, companion: strongCode)
        moduleMemory.save(to: defaults)
    }

    private func rememberCurrentLexiconQuery() {
        guard let key = memoryKey(for: activeLexiconPath) else { return }
        // Persist Strong as the query when known — never Spanish as the lexicon key
        let q = lexiconStrongForSearchBar ?? strongCode
        guard let q, !q.isEmpty else { return }
        moduleMemory.lexiconQueries[key] = .init(query: q, companion: selectedWord)
        moduleMemory.save(to: defaults)
    }

    /// Remember the **current** study query onto a module key (so future cold opens match).
    private func stampStudyQuery(ontoLexiconPath path: String?) {
        guard let key = memoryKey(for: path) else { return }
        let q = lexiconStrongForSearchBar ?? strongCode
        guard let q, !q.isEmpty else { return }
        moduleMemory.lexiconQueries[key] = .init(query: q, companion: selectedWord)
        moduleMemory.save(to: defaults)
    }

    private func stampStudyQuery(ontoDictionaryPath path: String?) {
        guard let key = memoryKey(for: path),
              let q = selectedWord, StrongResolve.isPlausibleSpanishGloss(q) else { return }
        moduleMemory.dictionaryQueries[key] = .init(query: q, companion: strongCode)
        moduleMemory.save(to: defaults)
    }

    private func restoreDictionaryQuery(for path: String?) {
        guard let key = memoryKey(for: path),
              let state = moduleMemory.dictionaryQueries[key],
              !state.query.isEmpty else { return }
        selectedWord = state.query
        if let c = state.companion, !c.isEmpty { strongCode = c }
    }

    private func restoreLexiconQuery(for path: String?) {
        guard let key = memoryKey(for: path),
              let state = moduleMemory.lexiconQueries[key],
              !state.query.isEmpty else { return }
        if StrongNormalizer.looksLikeStrong(state.query) {
            let code = StrongNormalizer.normalize(state.query)
            strongCode = code
            lexiconQueryField = code
            if let c = state.companion, !c.isEmpty { selectedWord = c }
        } else if let c = state.companion, StrongNormalizer.looksLikeStrong(c) {
            // Legacy: query was Spanish, companion was Strong
            let code = StrongNormalizer.normalize(c)
            strongCode = code
            lexiconQueryField = code
            selectedWord = state.query
        } else {
            // Legacy Spanish-only memory — do not put Spanish in the search bar
            selectedWord = state.query
            lexiconQueryField = ""
        }
    }

    private func buildLexiconStudyContext() -> LexiconStudyContext {
        let strong = strongCode
        var related: [String] = []
        var originals: [String] = []

        if let strong {
            let target = Set(StrongNormalizer.candidates(strong))
            for tok in selectedVerseTokens where tok.kind == .word {
                let match = tok.strongCodes.contains { sc in
                    !Set(StrongNormalizer.candidates(sc)).isDisjoint(with: target)
                }
                if match {
                    let w = tok.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard StrongResolve.isPlausibleSpanishGloss(w) else { continue }
                    if !related.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) {
                        related.append(w)
                    }
                }
            }
        }

        // Prefer real Spanish (user tap / blu / lexicon gloss), never morphology noise
        related = related.filter { StrongResolve.isPlausibleSpanishGloss($0) }
        let hitSpanish = strongHits
            .map(\.spanish)
            .first(where: { StrongResolve.isPlausibleSpanishGloss($0) })
        // Lexicon article RV1960 glosses (when interlinear blu is • or missing)
        let lexiconGlosses: [String] = {
            guard let plain = lexiconEntry?.plain, !plain.isEmpty else { return [] }
            return StrongResolve.extractSpanishGlossesFromLexiconPlain(plain)
        }()
        var spanish = QueryNormalizer.preferredSpanishHeadword(
            [selectedWord, hitSpanish, related.first, lexiconGlosses.first].compactMap { $0 }
                .filter { StrongResolve.isPlausibleSpanishGloss($0) }
        )
        if let s = spanish {
            related.removeAll { $0.caseInsensitiveCompare(s) == .orderedSame }
            related.insert(s, at: 0)
        }
        // Surface related lexicon glosses too
        for g in lexiconGlosses where StrongResolve.isPlausibleSpanishGloss(g) {
            if !related.contains(where: { $0.caseInsensitiveCompare(g) == .orderedSame }) {
                related.append(g)
            }
        }

        // Prefer plain RV1960 companion Spanish; fall back to active Bible plain text
        let verseSpanish = companionVerseSpanish[verse]
            ?? chapterVerses.first(where: { $0.verse == verse })?.plain

        // Prefer resolved Greek/Hebrew from interlinear Strong’s resolve
        for hit in strongHits where !hit.greek.isEmpty {
            if StrongResolve.isMorphologyCode(hit.greek) || StrongResolve.isDottedAnalyticalMorph(hit.greek) {
                continue
            }
            if !originals.contains(hit.greek) {
                originals.append(hit.greek)
            }
        }
        // Lexicon headword (always present for Strong dictionary articles)
        if let plain = lexiconEntry?.plain,
           let head = StrongResolve.extractOriginalHeadwordFromLexiconPlain(plain),
           !originals.contains(head) {
            if originals.isEmpty {
                originals.insert(head, at: 0)
            } else if !originals.contains(where: { $0 == head }) {
                // Keep interlinear form first; add lexicon lemma as secondary
                originals.append(head)
            }
        }
        // Fallback: scan active verse raw for script runs near Strong
        if originals.isEmpty, let raw = chapterVerses.first(where: { $0.verse == verse })?.raw {
            originals = extractOriginalScriptSnippets(from: raw, strong: strong)
        }

        return LexiconStudyContext(
            spanishWord: spanish,
            strongCode: strong,
            relatedSpanish: related,
            verseSpanish: verseSpanish,
            locationLabel: locationLabel,
            originalSnippets: originals
        )
    }

    /// Plain Spanish for a verse from the RV1960 companion (if linked).
    func companionSpanish(for verseNumber: Int) -> String? {
        companionVerseSpanish[verseNumber]
    }

    /// Pull Hebrew / Greek runs from e-Sword interlinear HTML near a Strong.
    private func extractOriginalScriptSnippets(from raw: String, strong: String?) -> [String] {
        var out: [String] = []
        let clipped = raw.count > 8_000 ? String(raw.prefix(8_000)) : raw
        // Hebrew Unicode block (normal string so \u{…} expands)
        if let re = try? NSRegularExpression(pattern: "[\u{0590}-\u{05FF}\u{FB1D}-\u{FB4F}]{2,}", options: []) {
            let ns = NSRange(clipped.startIndex..., in: clipped)
            re.enumerateMatches(in: clipped, options: [], range: ns) { match, _, stop in
                guard let match, let r = Range(match.range, in: clipped) else { return }
                let s = String(clipped[r])
                if !out.contains(s) { out.append(s) }
                if out.count >= 6 { stop.pointee = true }
            }
        }
        // Greek
        if out.count < 6, let re = try? NSRegularExpression(pattern: "[\u{0370}-\u{03FF}\u{1F00}-\u{1FFF}]{2,}", options: []) {
            let ns = NSRange(clipped.startIndex..., in: clipped)
            re.enumerateMatches(in: clipped, options: [], range: ns) { match, _, stop in
                guard let match, let r = Range(match.range, in: clipped) else { return }
                let s = String(clipped[r])
                if !out.contains(s) { out.append(s) }
                if out.count >= 6 { stop.pointee = true }
            }
        }
        // Prefer snippets near Strong tag if we have a code
        if let strong, let range = clipped.range(of: strong, options: .caseInsensitive) {
            let start = clipped.index(range.lowerBound, offsetBy: -80, limitedBy: clipped.startIndex) ?? clipped.startIndex
            let end = clipped.index(range.upperBound, offsetBy: 80, limitedBy: clipped.endIndex) ?? clipped.endIndex
            let window = clipped[start..<end]
            let near = out.filter { window.contains($0) }
            if !near.isEmpty { return Array(near.prefix(4)) }
        }
        return Array(out.prefix(4))
    }

    /// Display title of the active Bible (for peeks).
    var activeBibleTitle: String? {
        guard let path = activeBiblePath,
              let mod = store?.modules.first(where: { $0.path == path }) else { return nil }
        return mod.title.isEmpty ? mod.filename : mod.title
    }

    var locationLabel: String {
        BibleBooks.reference(book: book, chapter: chapter, verse: verse)
    }

    var contextBannerText: String? {
        if isResolvingStrongs {
            var parts: [String] = [locationLabel]
            if let w = selectedWord, !w.isEmpty {
                parts.append("«\(w)»")
            }
            parts.append("Resolviendo griego/hebreo…")
            return parts.joined(separator: " · ")
        }

        // Prefer rich chip from interlinear resolve: «Gozaos» → G5463 χαίρετε (chairete)
        if let w = selectedWord, !w.isEmpty, let hit = strongHits.first {
            var chip = "«\(w)» → \(hit.strong)"
            if !hit.greek.isEmpty {
                chip += " \(hit.greek)"
            }
            if !hit.translit.isEmpty {
                chip += " (\(hit.translit))"
            }
            if strongHits.count > 1 {
                let extra = strongHits.dropFirst().prefix(2).map(\.strong).joined(separator: ", ")
                if !extra.isEmpty { chip += " · \(extra)" }
            }
            return "\(locationLabel) · \(chip)"
        }

        var parts: [String] = [locationLabel]
        if let w = selectedWord, !w.isEmpty {
            parts.append("«\(w)»")
        }
        if let s = strongCode, !s.isEmpty {
            parts.append("Strong \(s)")
        }
        if let note = strongResolveNote, !note.isEmpty, strongHits.isEmpty {
            // Short actionable note (install interlinear / no match)
            parts.append(note)
        }
        return parts.count > 1 ? parts.joined(separator: " · ") : nil
    }

    // MARK: - Highlights

    func highlightKey(book: Int? = nil, chapter: Int? = nil, verse: Int? = nil) -> String {
        "\(book ?? self.book):\(chapter ?? self.chapter):\(verse ?? self.verse)"
    }

    func highlightColor(for verse: Int) -> HighlightColor? {
        guard let raw = highlights[highlightKey(verse: verse)] else { return nil }
        return HighlightColor(rawValue: raw)
    }

    func setHighlight(_ color: HighlightColor?, verse: Int) {
        let key = highlightKey(verse: verse)
        if let color {
            highlights[key] = color.rawValue
        } else {
            highlights.removeValue(forKey: key)
        }
        persistHighlights()
    }

    // MARK: - Module selection

    /// Restore last modules (by path, then filename) before any heuristic defaults.
    func applyDefaultModules(from store: ModuleStore) {
        self.store = store

        activeBiblePath = resolveModule(
            path: activeBiblePath, filename: savedBibleFile, kind: .bible, store: store
        ) ?? preferredDefault(kind: .bible, store: store)

        activeCommentaryPath = resolveModule(
            path: activeCommentaryPath, filename: savedCommentaryFile, kind: .commentary, store: store
        ) ?? preferredDefault(kind: .commentary, store: store)

        activeDictionaryPath = resolveModule(
            path: activeDictionaryPath, filename: savedDictionaryFile, kind: .dictionary, store: store
        ) ?? preferredDefault(kind: .dictionary, store: store)

        activeLexiconPath = resolveModule(
            path: activeLexiconPath, filename: savedLexiconFile, kind: .lexicon, store: store
        ) ?? preferredDefault(kind: .lexicon, store: store)

        activeCrossReferencePath = resolveModule(
            path: activeCrossReferencePath, filename: savedCrossReferenceFile, kind: .commentary, store: store
        ) ?? crossReferenceModules(from: store).first?.path

        // Silent Strong map (iRV etc.) — never replaces the reading Bible.
        resolveInterlinearMapModule(from: store)

        // One-shot: if an old build forced iRV as the reading Bible, switch reading
        // back to plain RV1960 and keep iRV only as the silent map.
        migrateReadingBibleOffInterlinearIfNeeded(store: store)

        // Spanish companion only when the *reading* Bible is itself interlinear.
        resolveCompanionSpanishBible(from: store)

        // Sync filenames from resolved paths
        if let p = activeBiblePath { savedBibleFile = (p as NSString).lastPathComponent }
        if let p = activeCommentaryPath { savedCommentaryFile = (p as NSString).lastPathComponent }
        if let p = activeDictionaryPath { savedDictionaryFile = (p as NSString).lastPathComponent }
        if let p = activeLexiconPath { savedLexiconFile = (p as NSString).lastPathComponent }
        if let p = activeCrossReferencePath { savedCrossReferenceFile = (p as NSString).lastPathComponent }
        if let p = activeInterlinearPath { savedInterlinearFile = (p as NSString).lastPathComponent }
        if let p = companionSpanishBiblePath {
            savedCompanionSpanishFile = (p as NSString).lastPathComponent
        }

        persist()
    }

    /// Preferred **reading** Bible: plain RV1960, never interlinear.
    private func preferredReadingBible(store: ModuleStore) -> String? {
        let bibles = store.modules(of: .bible)
        if let plain = bibles.first(where: { isPlainRV1960($0) }) { return plain.path }
        if let rv = bibles.first(where: {
            let hay = ($0.title + $0.filename).lowercased()
            return hay.contains("reina") && hay.contains("valera")
                && !hay.contains("interlineal") && !hay.contains("interlinear")
                && !hay.contains("irv") && !$0.hasStrongs
        }) { return rv.path }
        // Any non-interlinear Bible
        if let plainish = bibles.first(where: { !isInterlinearOrStrongRV($0) }) {
            return plainish.path
        }
        return bibles.first?.path
    }

    /// Preferred silent Strong-map module (iRV / interlinear) — not for reading UI.
    private func preferredInterlinearMap(store: ModuleStore) -> ModuleInfo? {
        StrongResolve.rankedInterlinearModules(store.modules(of: .bible)).first
    }

    /// Wire `activeInterlinearPath` for background Spanish → Strong resolution.
    func resolveInterlinearMapModule(from store: ModuleStore) {
        self.store = store
        let bibles = store.modules(of: .bible)

        if let resolved = resolveModule(
            path: activeInterlinearPath,
            filename: savedInterlinearFile,
            kind: .bible,
            store: store
        ), let mod = bibles.first(where: { $0.path == resolved }),
           StrongResolve.interlinearCandidateScore(
               title: mod.title, filename: mod.filename,
               abbreviation: mod.abbreviation, hasStrongs: mod.hasStrongs
           ) > 0 {
            activeInterlinearPath = resolved
            interlinearMapLabel = mod.displayName
            savedInterlinearFile = mod.filename
            return
        }

        if let best = preferredInterlinearMap(store: store) {
            activeInterlinearPath = best.path
            interlinearMapLabel = best.displayName
            savedInterlinearFile = best.filename
            return
        }

        activeInterlinearPath = nil
        interlinearMapLabel = nil
        savedInterlinearFile = nil
    }

    /// Old builds set interlinear as the active reading Bible. Move it to the silent map
    /// and put plain RV1960 in the Biblia tab (once).
    private func migrateReadingBibleOffInterlinearIfNeeded(store: ModuleStore) {
        if defaults.bool(forKey: Keys.migratedPlainReading) { return }
        defer { defaults.set(true, forKey: Keys.migratedPlainReading) }

        guard let active = activeBiblePath, isStudyBible(path: active) else { return }

        // Keep that module as the silent Strong map
        if activeInterlinearPath == nil {
            activeInterlinearPath = active
            if let mod = store.modules.first(where: { $0.path == active }) {
                interlinearMapLabel = mod.displayName
                savedInterlinearFile = mod.filename
            }
        }
        // Put plain RV1960 in the reading tab when available
        if let plain = preferredReadingBible(store: store), plain != active {
            activeBiblePath = plain
            savedBibleFile = (plain as NSString).lastPathComponent
        }
    }

    /// Find plain RV1960 “as is” among installed Bibles (not interlinear / not Strong edition).
    func resolveCompanionSpanishBible(from store: ModuleStore) {
        self.store = store
        let bibles = store.modules(of: .bible)

        // Keep user/saved companion if still present
        if let resolved = resolveModule(
            path: companionSpanishBiblePath,
            filename: savedCompanionSpanishFile,
            kind: .bible,
            store: store
        ), let mod = bibles.first(where: { $0.path == resolved }), isPlainRV1960(mod) || !isStudyBible(path: resolved) {
            // Accept saved if not the same as active study bible, or if it's clearly plain RV
            if resolved != activeBiblePath {
                companionSpanishBiblePath = resolved
                companionBibleLabel = mod.displayName
                savedCompanionSpanishFile = mod.filename
                return
            }
        }

        // Prefer plain RV1960
        if let plain = bibles.first(where: { isPlainRV1960($0) && $0.path != activeBiblePath }) {
            companionSpanishBiblePath = plain.path
            companionBibleLabel = plain.displayName
            savedCompanionSpanishFile = plain.filename
            return
        }

        // Fallback: any non-Strong Spanish Reina-Valera that isn't the active interlinear
        if let rv = bibles.first(where: {
            let hay = ($0.title + $0.filename).lowercased()
            return hay.contains("reina") && hay.contains("valera")
                && !$0.hasStrongs
                && !hay.contains("interlineal")
                && $0.path != activeBiblePath
        }) {
            companionSpanishBiblePath = rv.path
            companionBibleLabel = rv.displayName
            savedCompanionSpanishFile = rv.filename
            return
        }

        // If active is interlinear and no plain found, clear companion
        if let active = activeBiblePath, isStudyBible(path: active) {
            companionSpanishBiblePath = nil
            companionBibleLabel = nil
        } else {
            // Active is already plain Spanish — no separate companion needed
            companionSpanishBiblePath = nil
            companionBibleLabel = nil
            companionVerseSpanish = [:]
        }
    }

    private func resolveModule(
        path: String?,
        filename: String?,
        kind: ModuleKind,
        store: ModuleStore
    ) -> String? {
        let list = store.modules(of: kind)
        if let path, FileManager.default.fileExists(atPath: path),
           list.contains(where: { $0.path == path }) {
            return path
        }
        // Same filename after re-import (path UUID / container may change)
        if let filename, !filename.isEmpty,
           let match = list.first(where: { $0.filename.compare(filename, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return match.path
        }
        // Partial: saved path's last component
        if let path {
            let name = (path as NSString).lastPathComponent
            if let match = list.first(where: { $0.filename.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return match.path
            }
        }
        return nil
    }

    /// Only used when the user has never chosen a module of this kind.
    private func preferredDefault(kind: ModuleKind, store: ModuleStore) -> String? {
        let list = store.modules(of: kind)
        switch kind {
        case .bible:
            // Reading default: plain RV1960 — interlinear is wired separately as silent map
            return preferredReadingBible(store: store)
        case .dictionary:
            return list.first(where: {
                let hay = ($0.title + $0.filename).lowercased()
                return hay.contains("strong") || hay.contains("vine") || hay.contains("exposit")
            })?.path ?? list.first?.path
        case .lexicon:
            return list.first(where: {
                let hay = ($0.title + $0.filename).lowercased()
                return hay.contains("strong") || hay.contains("multilex") || hay.contains("thayer")
            })?.path ?? list.first?.path
        case .commentary:
            return list.first?.path
        case .reference:
            return nil
        }
    }

    func setActiveModule(path: String?, kind: ModuleKind) {
        // Same module → no-op
        let previousPath: String?
        switch kind {
        case .bible: previousPath = activeBiblePath
        case .commentary: previousPath = activeCommentaryPath
        case .dictionary: previousPath = activeDictionaryPath
        case .lexicon: previousPath = activeLexiconPath
        case .reference: previousPath = nil
        }
        if path == previousPath { return }

        // Reading location is global — freeze it across any module swap so nothing
        // (legacy memory, async reload races, etc.) can jump book/chapter/verse.
        let lockedBook = book
        let lockedChapter = chapter
        let lockedVerse = verse

        switch kind {
        case .bible:
            // Keep global book/chapter/verse — only the text source changes.
            // (Never restore a per-version last place; that jumped e.g. Gen 3 → Zech 3.)
            activeBiblePath = path
            savedBibleFile = path.map { ($0 as NSString).lastPathComponent }
            selectedVerseTokens = []
            lastPresentedChapterKey = nil // force chapter reload for new module
            // Re-wire silent Strong map + Spanish companion; reading choice stays whatever user picked
            if let store {
                resolveInterlinearMapModule(from: store)
                resolveCompanionSpanishBible(from: store)
            }
        case .commentary:
            // Same passage; only the commentary module changes. Never change the study word.
            activeCommentaryPath = path
            savedCommentaryFile = path.map { ($0 as NSString).lastPathComponent }
            lastCommentaryKey = nil
        case .dictionary:
            rememberCurrentDictionaryQuery()
            activeDictionaryPath = path
            savedDictionaryFile = path.map { ($0 as NSString).lastPathComponent }
            // Keep the word currently under study across ALL dictionary modules.
            if hasActiveStudyFocus {
                stampStudyQuery(ontoDictionaryPath: path)
            } else {
                restoreDictionaryQuery(for: path)
            }
        case .lexicon:
            rememberCurrentLexiconQuery()
            activeLexiconPath = path
            savedLexiconFile = path.map { ($0 as NSString).lastPathComponent }
            // Keep the SAME Strong + Spanish across every .lexi module. Never jump to an
            // old remembered lookup from another session on that file.
            if hasActiveStudyFocus {
                stampStudyQuery(ontoLexiconPath: path)
                if let code = lexiconStrongForSearchBar {
                    setLexiconSearchToStrong(code)
                }
                lexiconEntry = nil // force reload for this Strong in the new module
            } else {
                restoreLexiconQuery(for: path)
            }
        case .reference: break
        }

        // Re-assert passage after module change (safety net for study continuity).
        book = lockedBook
        chapter = lockedChapter
        verse = lockedVerse
        persist()
        scheduleModuleChangeReload(kind: kind)
    }

    // MARK: - Study links (refs / Strongs inside module text)

    func openStudyLink(_ link: StudyLink) {
        activePeek = StudyPeek(link: link)
    }

    func dismissPeek() {
        activePeek = nil
    }

    /// Load verses for the popup (range inclusive). Keeps raw for red-letter rendering.
    func loadVersePeek(book: Int, chapter: Int, verse: Int, verseEnd: Int) async throws -> [VerseRow] {
        guard let store, let path = activeBiblePath else {
            throw ModuleError.notFound
        }
        let rows = try await store.loadChapterAsync(modulePath: path, book: book, chapter: chapter)
        let lo = min(verse, verseEnd)
        let hi = max(verse, verseEnd)
        return rows.filter { $0.verse >= lo && $0.verse <= hi }
    }

    /// Load lexicon definition for a Strong code (popup).
    func loadStrongPeek(code: String) async throws -> DictEntry? {
        guard let store else { return nil }
        let path = activeLexiconPath
            ?? store.modules(of: .lexicon).first(where: {
                let hay = ($0.title + $0.filename).lowercased()
                return hay.contains("strong") || hay.contains("thayer") || hay.contains("multilex")
            })?.path
            ?? store.modules(of: .lexicon).first?.path
        guard let path else { return nil }
        let q = StrongNormalizer.normalize(code)
        return try await store.lookupLexiconAsync(modulePath: path, strong: q)
    }

    /// Schedule study reloads serially; cancels previous in-flight work.
    private func scheduleStudyReload(_ work: @escaping @MainActor () async -> Void) {
        studyLoadTask?.cancel()
        studyLoadTask = Task { @MainActor in
            await work()
        }
    }

    // MARK: - Recent verses

    /// Push a location to the front of the last-10 list (deduped). Safe to call often.
    func trackRecentVerse(book: Int? = nil, chapter: Int? = nil, verse: Int? = nil) {
        let b = book ?? self.book
        let c = chapter ?? self.chapter
        let v = verse ?? self.verse
        guard b >= 1, b <= 66, c >= 1, v >= 1 else { return }
        let entry = RecentVerse(book: b, chapter: c, verse: v)
        var next = recentVerses.filter { $0.id != entry.id }
        next.insert(entry, at: 0)
        if next.count > Self.recentVersesLimit {
            next = Array(next.prefix(Self.recentVersesLimit))
        }
        recentVerses = next
        persistRecentVerses()
    }

    /// Jump from the recent-verses menu.
    func openRecentVerse(_ entry: RecentVerse) {
        goTo(book: entry.book, chapter: entry.chapter, verse: entry.verse)
    }

    // MARK: - Cross-references (TSK-style commentary modules)

    /// Commentaries that look like cross-ref tools; if none installed, empty (UI explains).
    func crossReferenceModules(from store: ModuleStore) -> [ModuleInfo] {
        store.modules(of: .commentary).filter { $0.isCrossReferenceModule }
    }

    func setActiveCrossReference(path: String?) {
        activeCrossReferencePath = path
        savedCrossReferenceFile = path.map { ($0 as NSString).lastPathComponent }
        persist()
        Task { await reloadCrossReferences() }
    }

    @MainActor
    func reloadCrossReferences() async {
        guard let store else {
            crossReferenceEntries = []
            crossReferenceError = "Catálogo no listo."
            return
        }
        // Prefer saved/active; else first TSK-like module
        if activeCrossReferencePath == nil || !store.modules.contains(where: { $0.path == activeCrossReferencePath }) {
            activeCrossReferencePath = resolveModule(
                path: activeCrossReferencePath,
                filename: savedCrossReferenceFile,
                kind: .commentary,
                store: store
            ) ?? crossReferenceModules(from: store).first?.path
            if let p = activeCrossReferencePath {
                savedCrossReferenceFile = (p as NSString).lastPathComponent
            }
        }
        guard let path = activeCrossReferencePath else {
            crossReferenceEntries = []
            crossReferenceError = "Importe un módulo de referencias cruzadas (p. ej. TSK / TSKe) en Módulos."
            return
        }
        isLoadingCrossReferences = true
        crossReferenceError = nil
        defer { isLoadingCrossReferences = false }
        do {
            // Cross-ref tools are verse-scoped lists of <ref> links
            let entries = try await store.loadCommentaryAsync(
                modulePath: path,
                book: book,
                chapter: chapter,
                verse: verse,
                verseScope: true,
                chapterScope: false,
                bookScope: false
            )
            crossReferenceEntries = entries
            if entries.isEmpty {
                crossReferenceError = "Sin referencias cruzadas para \(locationLabel) en este módulo."
            }
        } catch {
            crossReferenceEntries = []
            crossReferenceError = error.localizedDescription
        }
    }

    // MARK: - Navigation

    func goTo(book: Int, chapter: Int, verse: Int = 1) {
        self.book = book
        self.chapter = max(1, chapter)
        self.verse = max(1, verse)
        selectedVerseTokens = []
        selectionSource = .navigation
        rememberPassagePicker(testamentIsOT: book <= 39, book: book)
        trackRecentVerse(book: self.book, chapter: self.chapter, verse: self.verse)
        persist()
        scheduleNavigationReload(includeChapter: true)
    }

    func selectVerse(_ v: Int) {
        verse = v
        selectionSource = .verseChange
        trackRecentVerse()
        persist()
        ensureTokensForSelectedVerse()
        // Invalidate commentary cache so verse/chapter scopes re-query for this verse
        lastCommentaryKey = nil
        // Same chapter — do not reload Bible text; only study panes (dict/lex/cmt).
        scheduleNavigationReload(includeChapter: false)
    }

    /// Uniform study-pane reload: dictionary (Spanish word) + lexicon (Strong) + commentary (verse/chapter).
    /// Call after word taps and after Strong resolve so all three resources stay linked.
    @MainActor
    func syncStudyResources(includeLexicon: Bool = true, includeDictionary: Bool = true, includeCommentary: Bool = true) async {
        if includeCommentary {
            lastCommentaryKey = nil
            await reloadCommentary()
            guard !Task.isCancelled else { return }
        }
        if includeLexicon, selectedWord != nil || strongCode != nil {
            await reloadLexicon()
            guard !Task.isCancelled else { return }
        }
        if includeDictionary, selectedWord != nil || strongCode != nil {
            await reloadDictionary()
            guard !Task.isCancelled else { return }
        }
        scheduleAvailabilityProbe()
    }

    /// Single cancellable cascade for BCV moves / version switches.
    /// Priority: paint Bible ASAP → commentary → dict/lex → deferred availability.
    private func scheduleNavigationReload(includeChapter: Bool) {
        navigationTask?.cancel()
        navigationTask = Task { @MainActor in
            if includeChapter {
                await reloadChapter()
                guard !Task.isCancelled else { return }
                ensureTokensForSelectedVerse()
            }
            await reloadCommentary()
            guard !Task.isCancelled else { return }
            if selectedWord != nil || strongCode != nil {
                await reloadDictionary()
                guard !Task.isCancelled else { return }
                await reloadLexicon()
            }
            // Cross-refs load only when the CR sheet asks (see CrossReferenceSheet).
            // Availability badges: debounced so they never stall the UI.
            scheduleAvailabilityProbe()
        }
    }

    private func scheduleModuleChangeReload(kind: ModuleKind) {
        navigationTask?.cancel()
        navigationTask = Task { @MainActor in
            switch kind {
            case .bible:
                // One chapter load only (BibleView.task may also fire — reloadChapter dedupes).
                await reloadChapter()
                guard !Task.isCancelled else { return }
                ensureTokensForSelectedVerse()
                // Commentary for same BCV after text is on screen
                await reloadCommentary()
            case .commentary:
                await reloadCommentary()
            case .dictionary:
                await reloadDictionary()
            case .lexicon:
                await reloadLexicon()
            case .reference:
                break
            }
            guard !Task.isCancelled else { return }
            scheduleAvailabilityProbe()
        }
    }

    private func scheduleAvailabilityProbe() {
        availabilityTask?.cancel()
        availabilityTask = Task(priority: .utility) { @MainActor in
            // Let the UI settle; skip if user already navigated again.
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await refreshAvailability()
        }
    }

    func nextChapter() {
        guard let info = BibleBooks.book(number: book) else { return }
        if chapter < info.chapters {
            goTo(book: book, chapter: chapter + 1, verse: 1)
        } else if book < 66 {
            goTo(book: book + 1, chapter: 1, verse: 1)
        }
    }

    func previousChapter() {
        if chapter > 1 {
            goTo(book: book, chapter: chapter - 1, verse: 1)
        } else if book > 1, let prev = BibleBooks.book(number: book - 1) {
            goTo(book: book - 1, chapter: prev.chapters, verse: 1)
        }
    }

    // MARK: - Word / Strong interaction

    /// Tap a Bible word (RV1960 Spanish or interlinear).
    /// Pipeline (Windows parity — always Strong in the Léxico bar):
    /// 1. Keep Spanish on `selectedWord` (word card only)
    /// 2. Map Spanish → H/G via silent interlinear (iRV 1960+)
    /// 3. Put **only** the Strong code in `lexiconQueryField`
    /// 4. Open Léxico and look up that Strong number — never Spanish
    func tapWord(_ token: VerseToken, verseNumber: Int) {
        verse = verseNumber
        let surface = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StrongResolve.isPlausibleSpanishGloss(surface)
                || StrongResolve.looksLikeStrongCode(surface) else {
            strongResolveNote = "Eso no es una palabra española (código de morfología del interlineal). Toque la palabra en azul/texto de lectura."
            return
        }
        // Keep the verse surface form for interlinear matching (do not stem-replace "corazón")
        let cleaned = surface

        if selectedVerseTokens.isEmpty {
            ensureTokensForSelectedVerse()
        }
        let wordTokens = selectedVerseTokens.filter(\.isTappableWord)
        let wordIndex = wordTokens.firstIndex(where: { $0.id == token.id })
        let linked: [String] = token.strongCodes.compactMap { StrongResolve.normalizeStrong($0) }

        selectedWord = cleaned
        selectionSource = .wordTap
        lexiconEntry = nil
        lexiconError = nil
        isLoadingLexicon = true
        focusedTab = .lexicon
        focusToken = UUID()

        if let primary = linked.first {
            // Interlinear Bible already has Strong on the token — put H/G in the bar NOW
            let title = activeBibleTitle ?? ""
            strongHits = linked.map {
                StrongHit(strong: $0, spanish: cleaned, greek: "", translit: "", sourceModule: title)
            }
            strongResolveNote = nil
            setLexiconSearchToStrong(primary)
            isResolvingStrongs = true // enrich original script in background
        } else if StrongResolve.looksLikeStrongCode(surface) {
            setLexiconSearchToStrong(surface)
            isResolvingStrongs = false
        } else {
            // Plain RV1960: must map via iRV before any lexicon open
            strongCode = nil
            strongHits = []
            strongResolveNote = nil
            lexiconQueryField = "" // empty until Strong lands — never Spanish
            isResolvingStrongs = true
        }

        rememberCurrentDictionaryQuery()
        rememberCurrentLexiconQuery()
        persist()

        let resolveWord = cleaned
        let resolveSurface = surface
        let resolveIndex = wordIndex
        let resolveVerse = verseNumber
        let hadLinkedStrong = linked.first != nil

        scheduleStudyReload {
            // 1) Always ensure we have a Strong code before lexicon lookup
            if self.lexiconStrongForSearchBar == nil || self.isResolvingStrongs {
                await self.resolveStrongsForCurrentSelection(
                    word: resolveWord,
                    surfaceWord: resolveSurface,
                    wordIndex: resolveIndex,
                    verseNumber: resolveVerse,
                    preferEnrichOnly: hadLinkedStrong
                )
                guard !Task.isCancelled else { return }
            }

            // 2) Put Strong in the search bar (the only thing that may appear there)
            if let code = self.lexiconStrongForSearchBar {
                self.setLexiconSearchToStrong(code)
            } else {
                self.isResolvingStrongs = false
                self.isLoadingLexicon = false
                self.lexiconEntry = nil
                self.lexiconError = self.strongResolveNote
                    ?? "No se pudo mapear «\(resolveWord)» a Strong. Importe «RV1960+ con números Strong» o iRV 1960+ en Módulos (mapa en segundo plano mientras lee Reina Valera 1960)."
                await self.reloadDictionary()
                return
            }

            // 3) Uniform sync: lexicon (Strong) + dictionary (Spanish) + commentary (verse/chapter)
            if let code = self.lexiconStrongForSearchBar {
                self.setLexiconSearchToStrong(code)
            }
            await self.syncStudyResources(
                includeLexicon: true,
                includeDictionary: true,
                includeCommentary: true
            )
            if let code = self.lexiconStrongForSearchBar {
                self.setLexiconSearchToStrong(code)
            }
        }
    }

    func tapStrong(_ code: String, nearbyWord: String? = nil, verseNumber: Int? = nil) {
        if let verseNumber {
            verse = verseNumber
        }
        ensureTokensForSelectedVerse()
        let normalized = StrongNormalizer.normalize(code)

        // Prefer Spanish that is *linked* to this Strong (token.strongCodes), then nearby gloss.
        let linkedSpanish = spanishGlossLinkedToStrong(normalized)
        if let linkedSpanish {
            selectedWord = QueryNormalizer.preferredSpanishHeadword(
                QueryNormalizer.dictionaryVariants(linkedSpanish)
            ) ?? linkedSpanish
        } else if let nearbyWord, StrongResolve.isPlausibleSpanishGloss(nearbyWord) {
            selectedWord = QueryNormalizer.preferredSpanishHeadword(
                QueryNormalizer.dictionaryVariants(nearbyWord)
            ) ?? nearbyWord
        } else if let existing = selectedWord, StrongResolve.isPlausibleSpanishGloss(existing) {
            // keep existing Spanish only if it is not a leftover from a previous Strong
        } else {
            selectedWord = nil
        }

        setLexiconSearchToStrong(normalized)
        strongHits = [
            StrongHit(
                strong: normalized,
                spanish: selectedWord ?? "",
                greek: "",
                translit: "",
                sourceModule: ""
            ),
        ]
        strongResolveNote = nil
        // Always reverse-resolve against interlinear so Spanish + Hebrew/Greek fill for every H/G
        isResolvingStrongs = true
        selectionSource = .strongTap
        lexiconEntry = nil
        lexiconError = nil
        isLoadingLexicon = true
        focusedTab = .lexicon
        focusToken = UUID()
        rememberCurrentDictionaryQuery()
        rememberCurrentLexiconQuery()
        persist()

        let resolveVerse = verse
        let resolveCode = normalized
        scheduleStudyReload {
            await self.enrichFromStrongCode(resolveCode, verseNumber: resolveVerse)
            guard !Task.isCancelled else { return }
            self.setLexiconSearchToStrong(resolveCode)
            await self.syncStudyResources(
                includeLexicon: true,
                includeDictionary: true,
                includeCommentary: true
            )
            self.setLexiconSearchToStrong(resolveCode)
        }
    }

    /// Spanish word in the reading verse whose token is linked to this Strong code.
    private func spanishGlossLinkedToStrong(_ code: String) -> String? {
        let target = Set(StrongNormalizer.candidates(code))
        guard !target.isEmpty else { return nil }
        if let gloss = selectedVerseTokens.first(where: { tok in
            tok.kind == .word
                && StrongResolve.isPlausibleSpanishGloss(tok.text)
                && tok.strongCodes.contains {
                    !Set(StrongNormalizer.candidates($0)).isDisjoint(with: target)
                }
        })?.text {
            return gloss
        }
        return nil
    }

    /// Reverse Strong → Spanish + original script via silent interlinear (current verse).
    @MainActor
    private func enrichFromStrongCode(_ code: String, verseNumber: Int) async {
        guard let store else {
            isResolvingStrongs = false
            return
        }
        if activeInterlinearPath == nil
            || !store.modules.contains(where: { $0.path == activeInterlinearPath }) {
            resolveInterlinearMapModule(from: store)
        }
        let bibles = store.modules(of: .bible)
        var candidates: [ModuleInfo] = []
        if let ip = activeInterlinearPath,
           let mod = bibles.first(where: { $0.path == ip }) {
            candidates.append(mod)
        }
        for mod in StrongResolve.rankedInterlinearModules(bibles) {
            if !candidates.contains(where: { $0.path == mod.path }) {
                candidates.append(mod)
            }
        }
        if let ap = activeBiblePath,
           let active = bibles.first(where: { $0.path == ap }),
           active.hasStrongs || isStudyBible(path: ap),
           !candidates.contains(where: { $0.path == ap }) {
            candidates.append(active)
        }
        guard !candidates.isEmpty else {
            isResolvingStrongs = false
            return
        }
        do {
            let result = try await store.resolveStrongsAsync(
                bookNumber: book,
                chapter: chapter,
                verse: verseNumber,
                word: code,
                wordIndex: nil,
                interlinearModules: candidates
            )
            guard !Task.isCancelled else { return }
            guard strongCode.map({ StrongNormalizer.normalize($0) }) == StrongNormalizer.normalize(code)
                    || strongCode == nil else { return }
            applyStrongResolve(result)
            if !result.interlinearPath.isEmpty {
                activeInterlinearPath = result.interlinearPath
                interlinearMapLabel = result.interlinearTitle
                savedInterlinearFile = (result.interlinearPath as NSString).lastPathComponent
            }
        } catch is CancellationError {
            return
        } catch {
            isResolvingStrongs = false
        }
    }

    /// Apply a resolve result onto selection state.
    private func applyStrongResolve(_ result: ResolveStrongsResult) {
        isResolvingStrongs = false
        // Keep the Spanish the user actually tapped (or typed). Interlinear blu may
        // differ slightly (deleitarás vs deleitate); never replace with morph junk.
        let bluSpanish = result.hits
            .map(\.spanish)
            .first(where: { StrongResolve.isPlausibleSpanishGloss($0) })
        let userSpanish = QueryNormalizer.preferredSpanishHeadword(
            [selectedWord, bluSpanish, result.word].compactMap { $0 }
                .filter { StrongResolve.isPlausibleSpanishGloss($0) }
        )
        strongHits = result.hits.map { hit in
            var h = hit
            if !StrongResolve.isPlausibleSpanishGloss(h.spanish) {
                h.spanish = userSpanish ?? ""
            } else if let u = userSpanish, StrongResolve.scoreTokenMatch(word: u, spanish: h.spanish) >= 70 {
                // Prefer the surface form from the reading Bible when it matches the blu gloss
                h.spanish = u
            }
            if StrongResolve.isMorphologyCode(h.translit) || StrongResolve.isDottedAnalyticalMorph(h.translit) {
                h.translit = ""
            }
            // Never surface morph codes as "original script"
            if StrongResolve.isMorphologyCode(h.greek) || StrongResolve.isDottedAnalyticalMorph(h.greek) {
                h.greek = ""
            }
            return h
        }
        // If reverse Strong lookup left empty hits, keep at least the code
        if strongHits.isEmpty, let code = StrongResolve.normalizeStrong(result.word)
            ?? strongCode.flatMap({ StrongResolve.normalizeStrong($0) }) {
            strongHits = [
                StrongHit(
                    strong: code,
                    spanish: userSpanish ?? "",
                    greek: "",
                    translit: "",
                    sourceModule: result.interlinearTitle
                ),
            ]
        }
        strongResolveNote = result.note.isEmpty ? nil : result.note
        if let first = strongHits.first {
            // Windows: Strong code is the lexicon search key — never leave Spanish in the bar
            setLexiconSearchToStrong(first.strong)
        }
        // Spanish is for the word card / dictionary only — never for lexiconQueryField
        if let u = userSpanish {
            selectedWord = u
        } else if let blu = strongHits.map(\.spanish).first(where: { StrongResolve.isPlausibleSpanishGloss($0) }) {
            selectedWord = blu
        }
        rememberCurrentDictionaryQuery()
        rememberCurrentLexiconQuery()
        persist()
    }

    /// Universal for **every** lexicon module (Strong, Swanson, Chávez, Tuggy, Multilexico, …):
    /// merge lemma + pronunciation into study state. Never replaces the Spanish word the
    /// user is studying when it is already a plausible gloss.
    private func fillSpanishAndOriginalFromLexiconEntry(_ entry: DictEntry) {
        let plain = entry.plain
        guard !plain.isEmpty else { return }

        let glosses = StrongResolve.extractSpanishGlossesFromLexiconPlain(plain)
        let original: String = {
            if !entry.originalScript.isEmpty { return entry.originalScript }
            return StrongResolve.extractOriginalHeadwordFromLexiconPlain(plain) ?? ""
        }()
        let translit: String = {
            if !entry.pronunciation.isEmpty,
               StrongResolve.isPlausibleTranslitToken(entry.pronunciation) {
                return entry.pronunciation
            }
            return StrongResolve.extractTranslitFromLexiconPlain(plain) ?? ""
        }()

        // Never invent a different Spanish headword when the user already has one
        let keepSpanish = selectedWord.flatMap { StrongResolve.isPlausibleSpanishGloss($0) ? $0 : nil }
        if keepSpanish == nil, let first = glosses.first {
            selectedWord = first
        }

        let code = strongCode
            ?? strongHits.first.flatMap { StrongResolve.normalizeStrong($0.strong) }
            ?? (StrongNormalizer.looksLikeStrong(entry.topic) ? StrongNormalizer.normalize(entry.topic) : nil)

        let spanishForHit = keepSpanish ?? selectedWord ?? glosses.first ?? ""

        if strongHits.isEmpty {
            if let code {
                strongHits = [
                    StrongHit(
                        strong: code,
                        spanish: spanishForHit,
                        greek: original,
                        translit: translit,
                        sourceModule: ""
                    ),
                ]
            }
        } else {
            // Update EVERY hit’s original/pronunciation from this module (module switch)
            strongHits = strongHits.map { hit in
                var h = hit
                // Keep the Spanish under study
                if let keepSpanish {
                    h.spanish = keepSpanish
                } else if !StrongResolve.isPlausibleSpanishGloss(h.spanish) {
                    h.spanish = spanishForHit
                }
                if !original.isEmpty {
                    h.greek = original
                }
                if !translit.isEmpty {
                    h.translit = translit
                }
                return h
            }
        }
        // Re-assert Strong bar so module switches never drop the code
        if let code {
            setLexiconSearchToStrong(code)
        }
        rememberCurrentLexiconQuery()
        rememberCurrentDictionaryQuery()
    }

    /// Map Spanish word → Strong’s using the **silent** interlinear map module.
    /// Reading Bible stays RV1960; iRV is only opened as SQLite lookup (never the UI text).
    @MainActor
    private func resolveStrongsForCurrentSelection(
        word: String,
        surfaceWord: String? = nil,
        wordIndex: Int?,
        verseNumber: Int,
        preferEnrichOnly: Bool
    ) async {
        guard let store else {
            isResolvingStrongs = false
            if strongCode == nil {
                strongResolveNote = "Catálogo no listo."
            }
            return
        }

        // Refresh silent map if missing
        if activeInterlinearPath == nil
            || !store.modules.contains(where: { $0.path == activeInterlinearPath }) {
            resolveInterlinearMapModule(from: store)
        }

        let bibles = store.modules(of: .bible)
        var candidates: [ModuleInfo] = []
        // 1) Wired silent map (iRV) — always first
        if let ip = activeInterlinearPath,
           let mod = bibles.first(where: { $0.path == ip }) {
            candidates.append(mod)
        }
        // 2) Other ranked interlinears (backup)
        for mod in StrongResolve.rankedInterlinearModules(bibles) {
            if !candidates.contains(where: { $0.path == mod.path }) {
                candidates.append(mod)
            }
        }
        // 3) If reading Bible itself has Strong tags, include as last resort
        if let ap = activeBiblePath,
           let active = bibles.first(where: { $0.path == ap }),
           active.hasStrongs || isStudyBible(path: ap),
           !candidates.contains(where: { $0.path == ap }) {
            candidates.append(active)
        }

        let probeWord = surfaceWord?.isEmpty == false ? (surfaceWord ?? word) : word

        guard !candidates.isEmpty else {
            isResolvingStrongs = false
            strongResolveNote = "Falta un mapa Strong en Módulos: «RV1960+ / con números Strong» o iRV 1960+. Siga leyendo Reina Valera 1960; Espada usa el mapa solo en segundo plano."
            return
        }

        do {
            // Try surface form, cleaned form, and with/without wordIndex until we get hits
            var result = try await store.resolveStrongsAsync(
                bookNumber: book,
                chapter: chapter,
                verse: verseNumber,
                word: probeWord,
                wordIndex: wordIndex,
                interlinearModules: candidates
            )
            if result.hits.isEmpty, probeWord.caseInsensitiveCompare(word) != .orderedSame {
                result = try await store.resolveStrongsAsync(
                    bookNumber: book,
                    chapter: chapter,
                    verse: verseNumber,
                    word: word,
                    wordIndex: wordIndex,
                    interlinearModules: candidates
                )
            }
            // Positional index from plain RV often misaligns with interlinear — retry without index
            if result.hits.isEmpty, wordIndex != nil {
                result = try await store.resolveStrongsAsync(
                    bookNumber: book,
                    chapter: chapter,
                    verse: verseNumber,
                    word: probeWord,
                    wordIndex: nil,
                    interlinearModules: candidates
                )
            }
            if result.hits.isEmpty, wordIndex != nil, probeWord.caseInsensitiveCompare(word) != .orderedSame {
                result = try await store.resolveStrongsAsync(
                    bookNumber: book,
                    chapter: chapter,
                    verse: verseNumber,
                    word: word,
                    wordIndex: nil,
                    interlinearModules: candidates
                )
            }
            guard !Task.isCancelled else { return }
            let stillSelected = selectedWord == word
                || selectedWord?.caseInsensitiveCompare(word) == .orderedSame
                || (surfaceWord.map { selectedWord?.caseInsensitiveCompare($0) == .orderedSame } ?? false)
                || selectedWord == nil
            guard stillSelected else { return }

            if preferEnrichOnly, result.hits.isEmpty {
                // Keep the Strong we already have on the token
                if let existing = strongCode {
                    setLexiconSearchToStrong(existing)
                }
                isResolvingStrongs = false
                return
            }

            if preferEnrichOnly, !result.hits.isEmpty {
                if let existing = strongCode {
                    let match = result.hits.first {
                        StrongNormalizer.normalize($0.strong) == StrongNormalizer.normalize(existing)
                    } ?? result.hits.first
                    if let match {
                        strongHits = result.hits
                        setLexiconSearchToStrong(match.strong)
                    }
                } else {
                    applyStrongResolve(result)
                    return
                }
                strongResolveNote = result.note.isEmpty ? nil : result.note
                isResolvingStrongs = false
                rememberCurrentLexiconQuery()
                persist()
                return
            }

            applyStrongResolve(result)
            // Always push Strong into the bar after a successful map
            if let code = strongHits.first?.strong {
                setLexiconSearchToStrong(code)
            }
            if !result.interlinearPath.isEmpty {
                activeInterlinearPath = result.interlinearPath
                interlinearMapLabel = result.interlinearTitle
                savedInterlinearFile = (result.interlinearPath as NSString).lastPathComponent
            }
        } catch is CancellationError {
            return
        } catch {
            isResolvingStrongs = false
            if strongHits.isEmpty, strongCode == nil {
                strongResolveNote = error.localizedDescription
            }
        }
    }

    func clearSelection() {
        selectedWord = nil
        strongCode = nil
        strongHits = []
        strongResolveNote = nil
        isResolvingStrongs = false
        lexiconQueryField = ""
        dictionaryResults = []
        lexiconEntry = nil
        lexiconNeedsStrongsBible = false
        dictionaryAvailability = [:]
        lexiconAvailability = [:]
        persist()
    }

    func searchDictionary(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard StrongResolve.isPlausibleSpanishGloss(trimmed) || StrongResolve.looksLikeStrongCode(trimmed) else {
            dictionaryError = "«\(trimmed)» no parece español (¿código de morfología?). Escriba la palabra de la Biblia."
            return
        }
        let cleaned = QueryNormalizer.preferredSpanishHeadword(
            QueryNormalizer.dictionaryVariants(trimmed)
        ) ?? trimmed
        selectedWord = cleaned
        selectionSource = .search
        focusedTab = .dictionary
        focusToken = UUID()
        rememberCurrentDictionaryQuery()
        persist()
        scheduleStudyReload {
            await self.reloadDictionary()
            guard !Task.isCancelled else { return }
            self.scheduleAvailabilityProbe()
        }
    }

    func searchLexicon(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isStrong = StrongNormalizer.looksLikeStrong(trimmed) || StrongResolve.looksLikeStrongCode(trimmed)
        if isStrong {
            setLexiconSearchToStrong(trimmed)
            if let linked = spanishGlossLinkedToStrong(strongCode ?? trimmed) {
                selectedWord = linked
            }
            strongHits = [
                StrongHit(
                    strong: strongCode ?? trimmed,
                    spanish: selectedWord ?? "",
                    greek: "",
                    translit: "",
                    sourceModule: ""
                ),
            ]
            strongResolveNote = nil
            isResolvingStrongs = true
        } else {
            // Typed Spanish: keep Spanish as selectedWord for the card; clear bar until Strong maps
            let cleaned = QueryNormalizer.preferredSpanishHeadword(
                QueryNormalizer.dictionaryVariants(trimmed)
            ) ?? trimmed
            selectedWord = cleaned
            strongCode = nil
            strongHits = []
            strongResolveNote = nil
            isResolvingStrongs = true
            lexiconQueryField = ""
        }
        selectionSource = .search
        lexiconEntry = nil
        lexiconError = nil
        isLoadingLexicon = true
        focusedTab = .lexicon
        focusToken = UUID()
        rememberCurrentLexiconQuery()
        persist()
        let resolveCode = isStrong ? (strongCode ?? StrongNormalizer.normalize(trimmed)) : nil
        let resolveVerse = verse
        scheduleStudyReload {
            if let resolveCode {
                await self.enrichFromStrongCode(resolveCode, verseNumber: resolveVerse)
                guard !Task.isCancelled else { return }
                self.setLexiconSearchToStrong(resolveCode)
            }
            await self.reloadLexicon()
            guard !Task.isCancelled else { return }
            if let code = self.lexiconStrongForSearchBar {
                self.setLexiconSearchToStrong(code)
            }
            await self.reloadDictionary()
            guard !Task.isCancelled else { return }
            self.scheduleAvailabilityProbe()
        }
    }

    // MARK: - Loaders

    @MainActor
    func reloadChapter() async {
        guard let store, let path = activeBiblePath else {
            chapterVerses = []
            selectedVerseTokens = []
            chapterError = "Seleccione una Biblia en el menú de módulos."
            return
        }
        // File may have been deleted mid-import crash
        guard FileManager.default.fileExists(atPath: path) else {
            chapterVerses = []
            selectedVerseTokens = []
            chapterError = "El módulo de Biblia ya no está. Elija otro en el menú."
            activeBiblePath = nil
            return
        }
        // Hold the requested verse so a mid-load UI update cannot drift the place.
        let requestedBook = book
        let requestedChapter = chapter
        let requestedVerse = verse
        let chapterKey = "\(path)|\(requestedBook)|\(requestedChapter)"

        // Already showing this chapter (e.g. BibleView.task + setActiveModule raced).
        if lastPresentedChapterKey == chapterKey, !chapterVerses.isEmpty {
            return
        }
        // Another reload of the same key is already in flight.
        if loadingChapterKey == chapterKey {
            return
        }
        loadingChapterKey = chapterKey
        defer {
            if loadingChapterKey == chapterKey {
                loadingChapterKey = nil
            }
        }

        // Cache hit → no spinner (instant prev/next / revisit)
        let wasCached = store.chapterCache.verse(
            for: path, book: requestedBook, chapter: requestedChapter
        ) != nil
        if !wasCached {
            isLoadingChapter = true
        }
        chapterError = nil
        defer { isLoadingChapter = false }
        do {
            let loaded = try await store.loadChapterAsync(
                modulePath: path, book: requestedBook, chapter: requestedChapter
            )
            // If something else navigated while loading, don't clobber the new place.
            guard book == requestedBook, chapter == requestedChapter,
                  activeBiblePath == path else { return }
            chapterVerses = loaded
            lastPresentedChapterKey = chapterKey
            if chapterVerses.isEmpty {
                chapterError = "No hay versículos en este capítulo para esta Biblia."
            } else {
                // Same book/chapter; if this version has fewer verses, clamp to last
                // available (still the same chapter — never jump books).
                if !chapterVerses.contains(where: { $0.verse == requestedVerse }) {
                    verse = chapterVerses.map(\.verse).max() ?? requestedVerse
                    persist()
                } else {
                    verse = requestedVerse
                }
            }
            // Tokenize the selected verse so study taps work immediately on plain RV1960
            // (previously tokens stayed empty until the user re-selected the verse).
            selectedVerseTokens = []
            ensureTokensForSelectedVerse()
            // Warm neighbors for snappy ‹ › flips (utility I/O, cancelled on next jump)
            scheduleNeighborPrefetch(store: store, path: path, book: requestedBook, chapter: requestedChapter)
            // Companion Spanish is optional study sugar — never block version switch / UI.
            Task(priority: .utility) { @MainActor in
                await self.reloadCompanionSpanishChapter()
            }
        } catch is CancellationError {
            return
        } catch {
            chapterVerses = []
            selectedVerseTokens = []
            lastPresentedChapterKey = nil
            chapterError = error.localizedDescription
            companionVerseSpanish = [:]
        }
    }

    /// Prefetch previous + next chapter into RAM cache (does not change UI location).
    private func scheduleNeighborPrefetch(store: ModuleStore, path: String, book: Int, chapter: Int) {
        prefetchTask?.cancel()
        var pairs: [(book: Int, chapter: Int)] = []
        // Next
        if let info = BibleBooks.book(number: book) {
            if chapter < info.chapters {
                pairs.append((book, chapter + 1))
            } else if book < 66 {
                pairs.append((book + 1, 1))
            }
        }
        // Previous
        if chapter > 1 {
            pairs.append((book, chapter - 1))
        } else if book > 1, let prev = BibleBooks.book(number: book - 1) {
            pairs.append((book - 1, prev.chapters))
        }
        guard !pairs.isEmpty else { return }
        prefetchTask = Task(priority: .utility) {
            // Let the current frame settle before background I/O
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            store.prefetchChapters(modulePath: path, pairs: pairs)
        }
    }

    /// Load clean Spanish from companion RV1960 (same book/chapter as study Bible).
    @MainActor
    func reloadCompanionSpanishChapter() async {
        guard let store else {
            companionVerseSpanish = [:]
            return
        }
        // Re-resolve if missing
        if companionSpanishBiblePath == nil || companionSpanishBiblePath == activeBiblePath {
            resolveCompanionSpanishBible(from: store)
        }
        guard let cPath = companionSpanishBiblePath,
              cPath != activeBiblePath,
              FileManager.default.fileExists(atPath: cPath) else {
            companionVerseSpanish = [:]
            return
        }
        do {
            let rows = try await store.loadChapterAsync(modulePath: cPath, book: book, chapter: chapter)
            var map: [Int: String] = [:]
            for row in rows {
                // Prefer fully cleaned plain Spanish
                let plain = row.plain.isEmpty ? ESwordText.moduleFieldToPlain(row.raw) : row.plain
                if !plain.isEmpty {
                    map[row.verse] = plain
                }
            }
            companionVerseSpanish = map
            if companionBibleLabel == nil,
               let mod = store.modules.first(where: { $0.path == cPath }) {
                companionBibleLabel = mod.displayName
            }
        } catch {
            companionVerseSpanish = [:]
        }
    }

    /// Launch-safe chapter load: on failure, try a smaller non-interlinear Bible.
    @MainActor
    func reloadChapterSafely() async {
        await reloadChapter()
        if chapterError == nil, !chapterVerses.isEmpty { return }
        guard let store else { return }
        let bibles = store.modules(of: .bible)
        // Prefer a plain Spanish Bible for recovery (smaller memory footprint)
        let fallback = bibles.first(where: { mod in
            let hay = (mod.title + mod.abbreviation + mod.filename).lowercased()
            return !hay.contains("interlineal") && !hay.contains("strong")
        }) ?? bibles.first
        if let fallback, fallback.path != activeBiblePath {
            activeBiblePath = fallback.path
            persist()
            await reloadChapter()
        }
    }

    /// Low-memory / jetsam pressure: drop non-essential study payloads (keep BCV + module paths).
    @MainActor
    func handleMemoryPressure() {
        prefetchTask?.cancel()
        navigationTask?.cancel()
        availabilityTask?.cancel()
        lastPresentedChapterKey = nil
        lastCommentaryKey = nil
        loadingChapterKey = nil
        store?.chapterCache.shrink(to: 2)
        // Drop heavy chapter buffers; next scroll/reload refills them.
        if chapterVerses.count > 40 {
            // Keep a thin window around the current verse so the UI doesn't flash empty.
            let lo = max(1, verse - 8)
            let hi = verse + 8
            chapterVerses = chapterVerses.filter { $0.verse >= lo && $0.verse <= hi }
        }
        selectedVerseTokens = []
        dictionaryResults = []
        lexiconEntry = nil
        commentaryEntries = []
        companionVerseSpanish = [:]
        commentaryAvailability = [:]
        dictionaryAvailability = [:]
        lexiconAvailability = [:]
        store?.handleMemoryPressure()
    }

    /// Tokenize only the selected verse (avoids thousands of SwiftUI buttons per chapter).
    func ensureTokensForSelectedVerse() {
        guard let store,
              let row = chapterVerses.first(where: { $0.verse == verse }) else {
            selectedVerseTokens = []
            return
        }
        selectedVerseTokens = store.tokenizeVerse(raw: row.raw, verse: row.verse)
    }

    @MainActor
    func reloadDictionary() async {
        guard let store, let path = activeDictionaryPath else {
            dictionaryResults = []
            dictionaryError = "Seleccione un diccionario (solo uno a la vez)."
            return
        }
        // Build Spanish probes: user word + blu gloss + stems — never morph / Strong codes
        var probes: [String] = []
        func addProbe(_ raw: String?) {
            guard let raw else { return }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard StrongResolve.isPlausibleSpanishGloss(t) else { return }
            for v in QueryNormalizer.dictionaryVariants(t) where !probes.contains(v) {
                probes.append(v)
            }
        }
        addProbe(selectedWord)
        for hit in strongHits { addProbe(hit.spanish) }

        guard let primary = probes.first else {
            dictionaryResults = []
            dictionaryError = nil
            return
        }
        // Keep selectedWord as clean Spanish for UI / badges
        if let best = QueryNormalizer.preferredSpanishHeadword(probes) {
            selectedWord = best
        }

        isLoadingDictionary = true
        dictionaryError = nil
        defer { isLoadingDictionary = false }
        do {
            var results: [DictEntry] = []
            var seenTopics = Set<String>()
            // Try probes in order until we have hits (stem / infinitive forms for verbs)
            for q in probes.prefix(12) {
                let batch = try await store.lookupDictionaryAsync(modulePath: path, query: q)
                for e in batch {
                    let key = e.topic.lowercased()
                    if seenTopics.insert(key).inserted {
                        results.append(e)
                    }
                }
                if !results.isEmpty { break }
            }
            guard !Task.isCancelled else { return }
            dictionaryResults = results
            if dictionaryResults.isEmpty {
                dictionaryError = "Sin entrada para «\(primary)». En el menú superior, el punto verde marca diccionarios con coincidencia — pruébelos, o otra forma de la palabra."
            }
        } catch is CancellationError {
            return
        } catch {
            dictionaryResults = []
            dictionaryError = error.localizedDescription
        }
    }

    @MainActor
    func reloadLexicon() async {
        guard let store else {
            lexiconEntry = nil
            isLoadingLexicon = false
            isResolvingStrongs = false
            lexiconError = "Catálogo no listo."
            return
        }

        isLoadingLexicon = true
        lexiconError = nil
        defer {
            isLoadingLexicon = false
            isResolvingStrongs = false
        }

        // ── Step A: ensure we have a Strong code (Spanish → H/G via interlinear) ──
        var strongQuery = lexiconStrongForSearchBar
        if strongQuery == nil, let spanish = selectedWord, !spanish.isEmpty,
           StrongResolve.isPlausibleSpanishGloss(spanish) {
            isResolvingStrongs = true
            await resolveStrongsForCurrentSelection(
                word: spanish,
                surfaceWord: spanish,
                wordIndex: nil,
                verseNumber: verse,
                preferEnrichOnly: false
            )
            guard !Task.isCancelled else { return }
            strongQuery = lexiconStrongForSearchBar
            if let code = strongQuery {
                setLexiconSearchToStrong(code)
            }
        } else if let code = strongQuery {
            // Enrich original script if missing
            let needsOriginal = !strongHits.contains(where: { !$0.greek.isEmpty })
            if needsOriginal {
                isResolvingStrongs = true
                await enrichFromStrongCode(code, verseNumber: verse)
                guard !Task.isCancelled else { return }
                strongQuery = lexiconStrongForSearchBar ?? code
                setLexiconSearchToStrong(strongQuery ?? code)
            } else {
                setLexiconSearchToStrong(code)
            }
        }

        let rankedInter = StrongResolve.rankedInterlinearModules(store.modules(of: .bible))
        lexiconNeedsStrongsBible = strongQuery == nil && rankedInter.isEmpty && activeInterlinearPath == nil

        // ── Step B: Léxico is Strong-only. No Spanish headword lookup. ──
        guard let sq = strongQuery, StrongNormalizer.looksLikeStrong(sq) else {
            lexiconEntry = nil
            if lexiconNeedsStrongsBible {
                lexiconError = "Falta el mapa Strong (iRV 1960+) en Módulos. Se usa en segundo plano para convertir la palabra española a H/G."
            } else if let note = strongResolveNote, !note.isEmpty {
                lexiconError = note
            } else if let w = selectedWord, !w.isEmpty {
                lexiconError = "No se pudo mapear «\(w)» a un número Strong en este versículo."
            } else {
                lexiconError = "Toque una palabra en RV1960. Espada buscará el código Strong (H/G), no el español."
            }
            return
        }

        setLexiconSearchToStrong(sq)

        var lexPaths: [String] = []
        if let p = activeLexiconPath { lexPaths.append(p) }
        let preferred = store.modules(of: .lexicon).sorted { a, b in
            let sa = (a.title + a.filename).lowercased()
            let sb = (b.title + b.filename).lowercased()
            let pa = (sa.contains("strong") ? 2 : 0) + (sa.contains("thayer") || sa.contains("multilex") ? 1 : 0)
            let pb = (sb.contains("strong") ? 2 : 0) + (sb.contains("thayer") || sb.contains("multilex") ? 1 : 0)
            if pa != pb { return pa > pb }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        for m in preferred where !lexPaths.contains(m.path) {
            lexPaths.append(m.path)
        }

        guard !lexPaths.isEmpty else {
            lexiconEntry = nil
            lexiconError = "Importe un léxico Strong en Módulos."
            return
        }

        do {
            var entry: DictEntry?
            var hitPath: String?

            // Strong code only — ModuleDatabase.lexiconLookup rejects Spanish
            for path in lexPaths {
                do {
                    if let e = try await store.lookupLexiconAsync(modulePath: path, strong: sq) {
                        entry = e
                        hitPath = path
                        break
                    }
                } catch {
                    continue
                }
            }

            guard !Task.isCancelled else { return }
            lexiconEntry = entry

            if let entry {
                fillSpanishAndOriginalFromLexiconEntry(entry)
            }

            // Bar must remain the Strong code after any fill
            setLexiconSearchToStrong(sq)

            if let hitPath, hitPath != activeLexiconPath {
                activeLexiconPath = hitPath
                savedLexiconFile = (hitPath as NSString).lastPathComponent
                persist()
            }

            if lexiconEntry == nil {
                lexiconError = "Ningún léxico instalado tiene «\(sq)». Importe un léxico Strong (punto verde = tiene la entrada)."
            } else {
                lexiconNeedsStrongsBible = false
                lexiconError = nil
            }
        } catch is CancellationError {
            return
        } catch {
            lexiconEntry = nil
            lexiconError = error.localizedDescription
        }
    }

    @MainActor
    func reloadCommentary() async {
        guard let store, let path = activeCommentaryPath else {
            commentaryEntries = []
            lastCommentaryKey = nil
            commentaryError = "Seleccione un comentario (solo uno a la vez)."
            return
        }
        let b = book, c = chapter, v = verse
        let vs = commentaryVerseScope, cs = commentaryChapterScope, bs = commentaryBookScope
        let key = "\(path)|\(b)|\(c)|\(v)|\(vs)|\(cs)|\(bs)"
        if lastCommentaryKey == key, !commentaryEntries.isEmpty {
            return
        }

        isLoadingCommentary = true
        commentaryError = nil
        defer { isLoadingCommentary = false }
        do {
            let entries = try await store.loadCommentaryAsync(
                modulePath: path,
                book: b, chapter: c, verse: v,
                verseScope: vs, chapterScope: cs, bookScope: bs
            )
            guard !Task.isCancelled else { return }
            // Drop stale results if the user moved on while we decoded.
            guard book == b, chapter == c, verse == v,
                  activeCommentaryPath == path else { return }
            commentaryEntries = entries
            lastCommentaryKey = key
            if commentaryEntries.isEmpty {
                commentaryError = "No hay comentarios para \(locationLabel) con los filtros actuales."
            }
        } catch is CancellationError {
            return
        } catch {
            commentaryEntries = []
            lastCommentaryKey = nil
            commentaryError = error.localizedDescription
        }
    }

    /// Probe study modules for badges (serial IO — safe for concurrent taps).
    /// Prefer calling via `scheduleAvailabilityProbe()` so it never blocks reading.
    @MainActor
    func refreshAvailability() async {
        guard let store else { return }
        isProbingAvailability = true
        defer { isProbingAvailability = false }

        let b = book, c = chapter, v = verse
        // Dictionary badges: only real Spanish (never morph / bare Strong)
        let wordQ: String = {
            if let w = selectedWord, StrongResolve.isPlausibleSpanishGloss(w) { return w }
            if let s = strongHits.map(\.spanish).first(where: { StrongResolve.isPlausibleSpanishGloss($0) }) {
                return s
            }
            return ""
        }()
        // Lexicon badges: Strong code only (never Spanish — lexicon is H/G keyed)
        let strongQ: String = {
            if let s = strongCode, StrongNormalizer.looksLikeStrong(s) { return StrongNormalizer.normalize(s) }
            if let hit = strongHits.first, StrongNormalizer.looksLikeStrong(hit.strong) {
                return StrongNormalizer.normalize(hit.strong)
            }
            return ""
        }()
        let cmtPaths = store.modules(of: .commentary).map(\.path)
        // Skip dict/lex probes when there is nothing to match (was opening every module for nothing).
        let dictPaths = wordQ.isEmpty ? [] : store.modules(of: .dictionary).map(\.path)
        let lexPaths = strongQ.isEmpty && wordQ.isEmpty
            ? []
            : store.modules(of: .lexicon).map(\.path)

        // One serial pass on the store queue (async let was still serialized and thrashy).
        let cmtMap = await store.probeAvailabilityAsync(
            kind: .commentary, paths: cmtPaths,
            book: b, chapter: c, verse: v, query: ""
        )
        guard !Task.isCancelled else { return }
        commentaryAvailability = cmtMap

        if !dictPaths.isEmpty {
            let dictMap = await store.probeAvailabilityAsync(
                kind: .dictionary, paths: dictPaths,
                book: b, chapter: c, verse: v, query: wordQ
            )
            guard !Task.isCancelled else { return }
            dictionaryAvailability = dictMap
        } else {
            dictionaryAvailability = [:]
        }

        if !lexPaths.isEmpty {
            let lexMap = await store.probeAvailabilityAsync(
                kind: .lexicon, paths: lexPaths,
                book: b, chapter: c, verse: v, query: strongQ.isEmpty ? wordQ : strongQ
            )
            guard !Task.isCancelled else { return }
            lexiconAvailability = lexMap
        } else {
            lexiconAvailability = [:]
        }
    }

    @MainActor
    func refreshAll() async {
        await reloadChapter()
        ensureTokensForSelectedVerse()
        await reloadCommentary()
        if selectedWord != nil || strongCode != nil {
            await reloadDictionary()
            await reloadLexicon()
        }
        scheduleAvailabilityProbe()
    }

    /// After launch: restore last location modules AND study selection queries.
    @MainActor
    func restoreStudyQueries() async {
        if selectedWord != nil || strongCode != nil {
            await reloadDictionary()
            await reloadLexicon()
        }
        scheduleAvailabilityProbe()
    }

    private func persist() {
        defaults.set(book, forKey: Keys.book)
        defaults.set(chapter, forKey: Keys.chapter)
        defaults.set(verse, forKey: Keys.verse)
        defaults.set(activeBiblePath, forKey: Keys.bible)
        defaults.set(activeCommentaryPath, forKey: Keys.commentary)
        defaults.set(activeDictionaryPath, forKey: Keys.dictionary)
        defaults.set(activeLexiconPath, forKey: Keys.lexicon)
        defaults.set(activeCrossReferencePath, forKey: Keys.crossReference)
        defaults.set(savedBibleFile, forKey: Keys.bibleFile)
        defaults.set(savedCommentaryFile, forKey: Keys.commentaryFile)
        defaults.set(savedDictionaryFile, forKey: Keys.dictionaryFile)
        defaults.set(savedLexiconFile, forKey: Keys.lexiconFile)
        defaults.set(savedCrossReferenceFile, forKey: Keys.crossReferenceFile)
        defaults.set(selectedWord, forKey: Keys.selectedWord)
        defaults.set(strongCode, forKey: Keys.strongCode)
        defaults.set(companionSpanishBiblePath, forKey: Keys.companionSpanish)
        defaults.set(savedCompanionSpanishFile, forKey: Keys.companionSpanishFile)
        defaults.set(activeInterlinearPath, forKey: Keys.interlinear)
        defaults.set(savedInterlinearFile, forKey: Keys.interlinearFile)
    }

    private func persistRecentVerses() {
        if let data = try? JSONEncoder().encode(recentVerses) {
            defaults.set(data, forKey: Keys.recentVerses)
        }
    }

    private func persistHighlights() {
        if let data = try? JSONEncoder().encode(highlights) {
            defaults.set(data, forKey: Keys.highlights)
        }
    }
}
