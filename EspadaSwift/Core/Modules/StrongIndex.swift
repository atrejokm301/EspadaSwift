import Foundation
import GRDB

/// Reverse lookup for Strong's numbers: **code → every verse that uses it**.
///
/// e-Sword modules only store the forward direction — open a verse, read its `<num>` tags.
/// Answering "where else does H3068 appear?" means reading all 31 101 verses of the
/// interlinear and parsing each one, measured at **1 865 ms**. That is far too slow to
/// put behind a tap, which is why the app has never offered a concordance.
///
/// Precomputing the same information into an indexed table makes the question a single
/// keyed lookup. Building it is one pass over the Bible table (measured 1 695 ms, done
/// once in the background) producing ~370 000 rows.
///
/// The forward direction is deliberately **not** served from here: a word tap already
/// resolves in ~4 ms through `StrongResolve`, and duplicating that path would add a
/// second source of truth for no user-visible gain.
final class StrongIndex: @unchecked Sendable {

    /// Bump to force a rebuild when the schema or the extraction rule changes.
    private static let schemaVersion = 1

    private let dbQueue: DatabaseQueue
    private let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            // Index writes are large and fully rebuildable — durability is not worth the
            // cost here, and WAL keeps reads available while a rebuild runs.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = OFF")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try createSchema()
    }

    /// Default location alongside the module catalog cache.
    static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("EspadaSwift", isDirectory: true)
            .appendingPathComponent("strong-index.sqlite")
    }

    private func createSchema() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS Occurrence (
                    strong  TEXT NOT NULL,
                    book    INTEGER NOT NULL,
                    chapter INTEGER NOT NULL,
                    verse   INTEGER NOT NULL,
                    PRIMARY KEY (strong, book, chapter, verse)
                ) WITHOUT ROWID
                """)
            // Serves "which codes are in this verse?" without a second table.
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS OccurrenceByVerse
                ON Occurrence (book, chapter, verse)
                """)
            // Original-script word → Strong's code, so Hebrew and Greek printed inside a
            // lexicon article can be tapped the way verse references already are.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS Form (
                    form   TEXT NOT NULL,
                    strong TEXT NOT NULL,
                    PRIMARY KEY (form, strong)
                ) WITHOUT ROWID
                """)
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS Meta (key TEXT PRIMARY KEY, value TEXT)")
        }
    }

    // MARK: - Original-script forms

    /// Fold a Hebrew or Greek run to a comparable key.
    ///
    /// Prose in a lexicon is vocalised and inflected while a headword is not, so raw
    /// comparison almost never matches. Stripping diacritics (niqqud, Greek accents),
    /// normalising Hebrew final letters and final sigma, and dropping the interlinear's
    /// word-order digits lifted Chávez coverage from 39.5% to 63.8%.
    static func normalizeScriptForm(_ raw: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in raw.decomposedStringWithCanonicalMapping.unicodeScalars {
            let v = scalar.value
            // Combining marks: Hebrew points/accents and Greek diacritics.
            if (v >= 0x0300 && v <= 0x036F) || (v >= 0x0591 && v <= 0x05C7) { continue }
            if v >= 0x0030 && v <= 0x0039 { continue }   // word-order indices
            switch v {
            case 0x05DA: out.append("\u{05DB}")          // ך → כ
            case 0x05DD: out.append("\u{05DE}")          // ם → מ
            case 0x05DF: out.append("\u{05E0}")          // ן → נ
            case 0x05E3: out.append("\u{05E4}")          // ף → פ
            case 0x05E5: out.append("\u{05E6}")          // ץ → צ
            case 0x03C2: out.append("\u{03C3}")          // ς → σ
            default: out.append(scalar)
            }
        }
        return String(out).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs shorter than this are declension endings (`ατος`, `ης`), not words.
    /// Linking them would produce confident-looking nonsense.
    static let minimumFormLength = 3

    /// Strong's code for a Hebrew/Greek word, or nil when it cannot be resolved.
    /// Ambiguous forms (5% of the index) resolve to the lowest-numbered code, which is
    /// conventionally the base lemma rather than a derived form.
    func strong(forForm raw: String) -> String? {
        let key = Self.normalizeScriptForm(raw)
        guard key.count >= Self.minimumFormLength else { return nil }
        return try? dbQueue.read { db in
            let codes = try String.fetchAll(
                db, sql: "SELECT strong FROM Form WHERE form = ?", arguments: [key]
            )
            return codes.min { a, b in
                let na = Int(a.dropFirst()) ?? .max
                let nb = Int(b.dropFirst()) ?? .max
                return na == nb ? a < b : na < nb
            }
        } ?? nil
    }

    var formCount: Int {
        (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Form")
        }) ?? 0 ?? 0
    }

    // MARK: - Freshness

    /// Identity of the module an index was built from, so a switched or edited
    /// interlinear triggers a rebuild instead of serving stale verses.
    struct Source: Equatable, Sendable {
        let path: String
        let size: UInt64
        let modified: TimeInterval

        init(path: String) {
            self.path = path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            self.size = (attrs?[.size] as? UInt64) ?? 0
            self.modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }

        var fingerprint: String {
            "\(Self.schemaTag)|\((path as NSString).lastPathComponent)|\(size)|\(Int(modified))"
        }

        private static var schemaTag: String { "v\(StrongIndex.schemaVersion)" }
    }

    /// True when the index already matches this module and has content.
    func isCurrent(for source: Source) -> Bool {
        (try? dbQueue.read { db -> Bool in
            let stored = try String.fetchOne(
                db, sql: "SELECT value FROM Meta WHERE key = 'source'"
            )
            guard stored == source.fingerprint else { return false }
            return try Int.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM Occurrence)") == 1
        }) ?? false
    }

    var occurrenceCount: Int {
        (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Occurrence")
        }) ?? 0 ?? 0
    }

    // MARK: - Build

    /// One pass over an interlinear Bible, extracting `<num>` codes per verse.
    ///
    /// Runs in a single transaction: 370 000 individual commits would take minutes,
    /// one transaction takes about as long as the scan itself.
    /// Headwords from a Strong-keyed lexicon: `H3820 → לֵב`.
    ///
    /// The interlinear supplies inflected forms, but only for words the translators
    /// actually used; a lexicon supplies the citation form of every entry, including
    /// words the reader will meet in prose but not in the text. Measured together they
    /// resolve about three quarters of the Greek in Tuggy, against half from either alone.
    ///
    /// Only the first script run of each article is read — the lemma is always first, and
    /// parsing 14 000 full articles would cost far more than the whole rest of the build.
    func indexLexiconHeadwords(paths: [String]) throws -> Int {
        guard !paths.isEmpty else { return 0 }
        var added = 0

        try dbQueue.write { db in
            let insertForm = try db.makeStatement(
                sql: "INSERT OR IGNORE INTO Form (form, strong) VALUES (?, ?)"
            )
            for path in paths {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                var config = Configuration()
                config.readonly = true
                guard let reader = try? DatabaseQueue(path: path, configuration: config) else { continue }

                for table in ["Lexicon", "Dictionary"] {
                    let rows = try? reader.read { r -> [Row] in
                        try Row.fetchAll(
                            r,
                            sql: "SELECT Topic, substr(Definition, 1, 400) AS head FROM \"\(table)\""
                        )
                    }
                    guard let rows, !rows.isEmpty else { continue }

                    for row in rows {
                        guard let topic = row["Topic"] as String?,
                              let code = StrongResolve.normalizeStrong(topic),
                              let head = row["head"] as String? else { continue }
                        let decoded = ESwordText.decodeAllHTMLEntities(head)
                        guard let lemma = Self.firstScriptRun(in: decoded) else { continue }
                        let form = Self.normalizeScriptForm(lemma)
                        guard form.count >= Self.minimumFormLength else { continue }
                        try? insertForm.execute(arguments: [form, code])
                        added += 1
                    }
                    break
                }
            }
        }
        return added
    }

    /// First Hebrew/Greek run in a string, which in a lexicon article is the headword.
    static func firstScriptRun(in text: String) -> String? {
        var run = ""
        for ch in text {
            let isScript = ch.unicodeScalars.contains { s in
                let v = s.value
                return (v >= 0x0590 && v <= 0x05FF) || (v >= 0xFB1D && v <= 0xFB4F)
                    || (v >= 0x0370 && v <= 0x03FF) || (v >= 0x1F00 && v <= 0x1FFF)
            }
            if isScript {
                run.append(ch)
            } else if !run.isEmpty {
                if run.count >= 2 { return run }
                run = ""
            }
        }
        return run.count >= 2 ? run : nil
    }

    @discardableResult
    func rebuild(from source: Source, progress: ((Double) -> Void)? = nil) throws -> Int {
        var config = Configuration()
        config.readonly = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA mmap_size = 268435456")
            try db.execute(sql: "PRAGMA query_only = ON")
        }
        let reader = try DatabaseQueue(path: source.path, configuration: config)

        let pattern = try NSRegularExpression(
            pattern: #"(?i)<num>\s*([HG]\s*\d+)\s*</num>"#,
            options: []
        )
        // `<heb>רֵאשִׁית</heb>2 <num>H7225</num>` — the inflected form and the code it
        // carries. Harvesting these is what makes Hebrew prose resolvable, since a
        // lexicon only ever lists the uninflected headword.
        let formPattern = try NSRegularExpression(
            pattern: #"(?is)<(?:heb|grk)(?:\s[^>]*)?>(.*?)</(?:heb|grk)>.{0,80}?<num>\s*([HG]\s*\d+)\s*</num>"#,
            options: []
        )

        var inserted = 0
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM Occurrence")
            try db.execute(sql: "DELETE FROM Form")
            try db.execute(sql: "DELETE FROM Meta")

            let total = try reader.read { r in
                try Int.fetchOne(r, sql: "SELECT COUNT(*) FROM Bible")
            } ?? 0
            var done = 0

            let insert = try db.makeStatement(
                sql: "INSERT OR IGNORE INTO Occurrence (strong, book, chapter, verse) VALUES (?, ?, ?, ?)"
            )
            let insertForm = try db.makeStatement(
                sql: "INSERT OR IGNORE INTO Form (form, strong) VALUES (?, ?)"
            )

            try reader.read { r in
                let rows = try Row.fetchCursor(
                    r, sql: "SELECT Book, Chapter, Verse, Scripture FROM Bible"
                )
                while let row = try rows.next() {
                    done += 1
                    if done % 2_000 == 0, total > 0 {
                        progress?(Double(done) / Double(total))
                    }
                    guard let book = row["Book"] as Int?,
                          let chapter = row["Chapter"] as Int?,
                          let verse = row["Verse"] as Int?,
                          let scripture = row["Scripture"] as String?,
                          !scripture.isEmpty else { continue }

                    var seen = Set<String>()
                    let range = NSRange(scripture.startIndex..., in: scripture)
                    pattern.enumerateMatches(in: scripture, options: [], range: range) { match, _, _ in
                        guard let match, match.numberOfRanges > 1,
                              let r = Range(match.range(at: 1), in: scripture),
                              let code = StrongResolve.normalizeStrong(String(scripture[r])),
                              seen.insert(code).inserted else { return }
                        try? insert.execute(arguments: [code, book, chapter, verse])
                        inserted += 1
                    }

                    let formRange = NSRange(scripture.startIndex..., in: scripture)
                    formPattern.enumerateMatches(in: scripture, options: [], range: formRange) { match, _, _ in
                        guard let match, match.numberOfRanges > 2,
                              let wordRange = Range(match.range(at: 1), in: scripture),
                              let codeRange = Range(match.range(at: 2), in: scripture),
                              let code = StrongResolve.normalizeStrong(String(scripture[codeRange]))
                        else { return }
                        let form = Self.normalizeScriptForm(
                            String(scripture[wordRange])
                                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        )
                        guard form.count >= Self.minimumFormLength else { return }
                        try? insertForm.execute(arguments: [form, code])
                    }
                }
            }

            try db.execute(
                sql: "INSERT OR REPLACE INTO Meta (key, value) VALUES ('source', ?)",
                arguments: [source.fingerprint]
            )
        }
        progress?(1)
        return inserted
    }

    // MARK: - Queries

    /// One place a Strong's code is used.
    struct Occurrence: Hashable, Sendable {
        let book: Int
        let chapter: Int
        let verse: Int

        var label: String { BibleBooks.reference(book: book, chapter: chapter, verse: verse) }
    }

    /// Every verse using this code, in canonical order. `limit` caps very common words —
    /// H3068 alone appears in over 5 000 verses.
    func occurrences(of strong: String, limit: Int = 500) -> [Occurrence] {
        guard let code = StrongResolve.normalizeStrong(strong) else { return [] }
        return (try? dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT book, chapter, verse FROM Occurrence
                WHERE strong = ?
                ORDER BY book, chapter, verse
                LIMIT ?
                """,
                arguments: [code, limit]
            ).compactMap { row -> Occurrence? in
                guard let b = row["book"] as Int?,
                      let c = row["chapter"] as Int?,
                      let v = row["verse"] as Int? else { return nil }
                return Occurrence(book: b, chapter: c, verse: v)
            }
        }) ?? []
    }

    /// Total verses using this code, without materialising them.
    func occurrenceCount(of strong: String) -> Int {
        guard let code = StrongResolve.normalizeStrong(strong) else { return 0 }
        return (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Occurrence WHERE strong = ?", arguments: [code])
        }) ?? 0 ?? 0
    }

    /// Which codes appear in one verse — the cheap way to badge a verse without parsing it.
    func codes(inBook book: Int, chapter: Int, verse: Int) -> [String] {
        (try? dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT strong FROM Occurrence
                WHERE book = ? AND chapter = ? AND verse = ?
                ORDER BY strong
                """,
                arguments: [book, chapter, verse]
            )
        }) ?? []
    }
}
