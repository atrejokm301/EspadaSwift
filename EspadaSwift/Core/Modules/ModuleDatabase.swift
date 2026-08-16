import Foundation
import GRDB

/// Read-only access to a single e-Sword SQLite module file.
final class ModuleDatabase: @unchecked Sendable {
    let path: String
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        self.path = path
        var config = Configuration()
        config.readonly = true
        config.foreignKeysEnabled = false
        // Large modules: allow longer busy wait
        config.busyMode = .timeout(3)
        // Read-path tuning: faster chapter/dict hits on flash, lower battery thrash.
        // Safe because every module is opened read-only.
        config.prepareDatabase { db in
            // Memory-map the file when the OS allows (big win on Bible chapters).
            try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256 MB hint
            // ~8 MB page cache (negative = kibibytes)
            try db.execute(sql: "PRAGMA cache_size = -8000")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            // Extra safety: no writes even if a statement tries
            try db.execute(sql: "PRAGMA query_only = ON")
        }
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
    }

    func readDetails() throws -> (title: String, abbreviation: String, version: Int, strongs: Bool) {
        try dbQueue.read { db in
            var title = ""
            var abbr = ""
            var version = 0
            var strongs = false

            if let row = try Row.fetchOne(db, sql: "SELECT * FROM Details LIMIT 1") {
                title = stringValue(row, keys: ["Title", "title"]) ?? ""
                abbr = stringValue(row, keys: ["Abbreviation", "abbreviation"]) ?? ""
                if let v: Int = intValue(row, keys: ["Version", "version"]) {
                    version = v
                }
                if let s: Int = intValue(row, keys: ["Strongs", "strongs"]) {
                    strongs = s != 0
                } else if let b = boolValue(row, keys: ["Strongs", "strongs"]) {
                    strongs = b
                }
            }
            return (title, abbr, version, strongs)
        }
    }

    func tableExists(_ name: String) throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT 1 FROM sqlite_master
                WHERE type='table' AND name=? COLLATE NOCASE LIMIT 1
                """,
                arguments: [name]
            ) != nil
        }
    }

    /// Tiny sample only — never pull multi‑MB interlinear blobs into RAM during catalog scan.
    func sampleText(kind: ModuleKind) throws -> String {
        try dbQueue.read { db in
            let sqls: [String]
            switch kind {
            case .bible:
                // First 512 chars is enough for encryption / Strong heuristics
                sqls = ["SELECT substr(Scripture, 1, 512) FROM Bible LIMIT 1"]
            case .commentary:
                sqls = [
                    "SELECT substr(Comments, 1, 512) FROM VerseCommentary LIMIT 1",
                    "SELECT substr(Comments, 1, 512) FROM ChapterCommentary LIMIT 1",
                    "SELECT substr(Comments, 1, 512) FROM BookCommentary LIMIT 1",
                ]
            case .dictionary, .lexicon:
                sqls = [
                    "SELECT substr(Definition, 1, 512) FROM Lexicon LIMIT 1",
                    "SELECT substr(Definition, 1, 512) FROM Dictionary LIMIT 1",
                ]
            case .reference:
                sqls = ["SELECT substr(Content, 1, 512) FROM Reference LIMIT 1"]
            }
            for sql in sqls {
                if let s = try? String.fetchOne(db, sql: sql), !s.isEmpty {
                    return String(s.prefix(512))
                }
                if let data = try? Data.fetchOne(db, sql: sql) {
                    let text = bytesToText(data)
                    return String(text.prefix(512))
                }
            }
            return ""
        }
    }

    /// Sample several rows and score the module's encoding health.
    ///
    /// Deliberately spread with `ORDER BY rowid` offsets rather than a plain `LIMIT`:
    /// damage clusters (the Reina ligature only appears where the word needs it), so
    /// reading the first N rows understates it. Bounded so catalog scans stay quick.
    func readHealth(kind: ModuleKind) throws -> ModuleHealth {
        let columns: [(String, String)]
        switch kind {
        case .bible:
            columns = [("Bible", "Scripture")]
        case .commentary:
            columns = [
                ("VerseCommentary", "Comments"),
                ("ChapterCommentary", "Comments"),
                ("BookCommentary", "Comments"),
            ]
        case .dictionary, .lexicon:
            columns = [("Dictionary", "Definition"), ("Lexicon", "Definition")]
        case .reference:
            columns = [("Reference", "Content")]
        }

        return try dbQueue.read { db in
            var health = ModuleHealth()
            for (table, column) in columns {
                guard try tableExists(db, table) else { continue }
                // MAX(rowid) is an index lookup; COUNT(*) would scan the whole table and
                // these files reach 130 MB. Sparse rowids only make sampling coarser.
                guard let total = try Int.fetchOne(db, sql: "SELECT MAX(rowid) FROM \"\(table)\""),
                      total > 0 else { continue }
                // Up to 120 rows spread across the table, each clipped to 4 KB.
                let wanted = min(120, total)
                let stride = max(1, total / wanted)
                // Row-based fetch: e-Sword stores mixed/NULL cells and `String.fetchAll`
                // traps on those. `cellString` already handles NULL, BLOB and UTF-16.
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT substr("\(column)", 1, 4096) AS sample FROM "\(table)"
                    WHERE rowid % ? = 0
                    LIMIT ?
                    """,
                    arguments: [stride, wanted]
                )
                for row in rows {
                    let sample = cellString(row, "sample")
                    guard !sample.isEmpty else { continue }
                    health.accumulate(sample: ESwordText.decodeAllHTMLEntities(sample))
                }
                if health.sampledRows > 0 { break }
            }
            return health
        }
    }

    func loadChapter(book: Int, chapter: Int) throws -> [(verse: Int, scripture: String)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT Verse, Scripture FROM Bible
                WHERE Book=? AND Chapter=?
                ORDER BY Verse
                """,
                arguments: [book, chapter]
            )
            return rows.compactMap { row in
                guard let verse = intValue(row, keys: ["Verse", "verse"]) else { return nil }
                let scripture = cellString(row, "Scripture")
                return (verse, scripture)
            }
        }
    }

    /// Single verse raw Scripture (tags preserved — for interlinear Strong’s resolve).
    func loadVerse(book: Int, chapter: Int, verse: Int) throws -> String? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT Scripture FROM Bible
                WHERE Book=? AND Chapter=? AND Verse=?
                LIMIT 1
                """,
                arguments: [book, chapter, verse]
            ) else { return nil }
            return cellString(row, "Scripture")
        }
    }

    func loadCommentary(
        book: Int,
        chapter: Int,
        verse: Int,
        includeVerse: Bool,
        includeChapter: Bool,
        includeBook: Bool
    ) throws -> [StudyEntry] {
        try dbQueue.read { db in
            var out: [StudyEntry] = []

            if includeVerse, try tableExists(db, "VerseCommentary") {
                // Scope SQL to this chapter (and overlapping ranges) — never load the
                // entire book of comments (that was multi‑MB + freezes on big modules).
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT ChapterBegin, VerseBegin, ChapterEnd, VerseEnd, Comments
                    FROM VerseCommentary
                    WHERE Book=?
                      AND ChapterBegin <= ?
                      AND (ChapterEnd = 0 OR ChapterEnd >= ?)
                    """,
                    arguments: [book, chapter, chapter]
                )
                for row in rows {
                    let cb = intValue(row, keys: ["ChapterBegin", "chapterBegin"]) ?? 0
                    let vb = intValue(row, keys: ["VerseBegin", "verseBegin"]) ?? 0
                    let ce = intValue(row, keys: ["ChapterEnd", "chapterEnd"]) ?? 0
                    let ve = intValue(row, keys: ["VerseEnd", "verseEnd"]) ?? 0
                    let comments = cellString(row, "Comments")
                    guard !comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                    let endCh = ce == 0 ? cb : ce
                    let endV = ve == 0 ? vb : ve
                    let afterStart = chapter > cb || (chapter == cb && verse >= vb)
                    let beforeEnd = chapter < endCh || (chapter == endCh && verse <= endV)
                    let single = ce == 0 && ve == 0 && cb == chapter && vb == verse
                    guard single || (afterStart && beforeEnd) else { continue }

                    if ESwordText.looksEncrypted(comments) {
                        throw ModuleError.encrypted
                    }
                    let plain = Self.boundedPlain(comments)
                    guard !plain.isEmpty else { continue }
                    let label: String
                    if cb == endCh && vb == endV {
                        label = "v.\(vb)"
                    } else if cb == endCh {
                        label = "v.\(vb)–\(endV)"
                    } else {
                        label = "\(cb):\(vb)–\(endCh):\(endV)"
                    }
                    out.append(StudyEntry(scope: "verse", label: label, plain: plain, html: plain))
                }
            }

            if includeChapter, try tableExists(db, "ChapterCommentary") {
                if let row = try Row.fetchOne(
                    db,
                    sql: "SELECT Comments FROM ChapterCommentary WHERE Book=? AND Chapter=?",
                    arguments: [book, chapter]
                ) {
                    let comments = cellString(row, "Comments")
                    if !comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let plain = Self.boundedPlain(comments)
                        if !plain.isEmpty {
                            out.append(StudyEntry(
                                scope: "chapter",
                                label: "Cap. \(chapter)",
                                plain: plain,
                                html: plain
                            ))
                        }
                    }
                }
            }

            if includeBook, try tableExists(db, "BookCommentary") {
                if let row = try Row.fetchOne(
                    db,
                    sql: "SELECT Comments FROM BookCommentary WHERE Book=?",
                    arguments: [book]
                ) {
                    let comments = cellString(row, "Comments")
                    if !comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let plain = Self.boundedPlain(comments)
                        if !plain.isEmpty {
                            out.append(StudyEntry(
                                scope: "book",
                                label: "Libro",
                                plain: plain,
                                html: plain
                            ))
                        }
                    }
                }
            }

            return out
        }
    }

    func dictionaryLookup(query: String, limit: Int = 20) throws -> [DictEntry] {
        let variants = QueryNormalizer.dictionaryVariants(query)
        guard !variants.isEmpty else { return [] }
        // Few probes for LIKE paths (index-friendly prefix). Full variant list is equality-only.
        let primary = QueryNormalizer.primaryDictionaryProbes(query)
        return try dbQueue.read { db in
            guard let schema = try topicSchema(db, prefer: "dictionary") else { return [] }

            // Phase 1: pure equality — one indexed query (TopicIndex). No LIKE, no ORDER BY length.
            // Benchmark: ~0.1ms vs ~200ms+ for OR Topic LIKE on large modules.
            let exact = try fetchEqualTopics(db, schema: schema, topics: variants, limit: limit)
            if !exact.isEmpty { return exact }

            // Phase 2: DRAE-style "lemma, gender" / "lemma (…)" — prefix LIKE uses TopicIndex.
            let lemma = try fetchLemmaTopics(db, schema: schema, probes: primary, limit: limit)
            if !lemma.isEmpty { return lemma }

            // Phase 3: autocomplete prefix only if nothing matched (still no mid-word %query%).
            let prefixProbes = primary.filter { $0.count >= 4 }
            return try fetchPrefixTopics(db, schema: schema, probes: prefixProbes, limit: min(limit, 12))
        }
    }

    /// Léxico is Strong-number only (H3068 / G25). Never look up Spanish surface forms here —
    /// Spanish→Strong mapping happens in StudySession via the interlinear map first.
    func lexiconLookup(strong: String) throws -> DictEntry? {
        let raw = strong.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Reject plain Spanish (and any non-Strong query). Callers must pass H/G codes.
        let isStrong = StrongNormalizer.looksLikeStrong(raw)
            || StrongResolve.normalizeStrong(raw) != nil
            || (raw.allSatisfy(\.isNumber) && raw.count <= 5)
        guard isStrong else { return nil }

        return try dbQueue.read { db in
            guard let schema = try topicSchema(db, prefer: "lexicon") else { return nil }
            let tCol = schema.topicCol
            let dCol = schema.definitionCol
            let table = schema.table

            // Exact Strong topic match only (with zero-padding variants from StrongNormalizer)
            for c in StrongNormalizer.candidates(raw) {
                if let row = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT "\(tCol)", "\(dCol)" FROM "\(table)"
                    WHERE "\(tCol)" = ? COLLATE NOCASE
                    LIMIT 1
                    """,
                    arguments: [c]
                ) {
                    let topic = cellString(row, tCol)
                    let def = cellString(row, dCol)
                    if ESwordText.looksEncrypted(def) { continue }
                    let entry = Self.makeStudyEntry(topic: topic, definition: def)
                    if entry.plain.isEmpty { continue }
                    return entry
                }
            }
            return nil
        }
    }

    /// Fast existence check for module picker badges (indexed equality first).
    func hasDictionaryHit(query: String) throws -> Bool {
        let variants = QueryNormalizer.dictionaryVariants(query)
        guard !variants.isEmpty else { return false }
        return try dbQueue.read { db in
            guard let schema = try topicSchema(db, prefer: "dictionary") else { return false }
            if try topicEqualsAny(db, schema: schema, topics: variants) { return true }
            let primary = QueryNormalizer.primaryDictionaryProbes(query)
            for q in primary {
                if try topicExists(db, schema: schema, query: q, mode: .exact) { return true }
            }
            for q in primary where q.count >= 4 {
                if try topicExists(db, schema: schema, query: q, mode: .prefix) { return true }
            }
            return false
        }
    }

    func hasLexiconHit(query: String) throws -> Bool {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        // Strong codes only (same rule as lexiconLookup)
        let isStrong = StrongNormalizer.looksLikeStrong(raw)
            || StrongResolve.normalizeStrong(raw) != nil
            || (raw.allSatisfy(\.isNumber) && raw.count <= 5)
        guard isStrong else { return false }
        return try dbQueue.read { db in
            guard let schema = try topicSchema(db, prefer: "lexicon") else { return false }
            for c in StrongNormalizer.candidates(raw) {
                if try topicExactExists(db, schema: schema, topic: c) { return true }
            }
            return false
        }
    }

    func hasCommentaryHit(book: Int, chapter: Int, verse: Int) throws -> Bool {
        try dbQueue.read { db in
            // Prefer indexed equality checks — avoid loading hundreds of rows (jetsam/crash risk)
            if try tableExists(db, "VerseCommentary") {
                if try Row.fetchOne(
                    db,
                    sql: """
                    SELECT 1 FROM VerseCommentary
                    WHERE Book=? AND ChapterBegin=? AND VerseBegin=?
                    LIMIT 1
                    """,
                    arguments: [book, chapter, verse]
                ) != nil { return true }
                // Range coverage (common in multi-verse comments)
                if try Row.fetchOne(
                    db,
                    sql: """
                    SELECT 1 FROM VerseCommentary
                    WHERE Book=?
                      AND ChapterBegin <= ?
                      AND (ChapterEnd = 0 OR ChapterEnd >= ?)
                      AND VerseBegin <= ?
                      AND (VerseEnd = 0 OR VerseEnd >= ? OR (ChapterEnd > 0 AND ChapterEnd > ChapterBegin))
                    LIMIT 1
                    """,
                    arguments: [book, chapter, chapter, verse, verse]
                ) != nil { return true }
            }
            if try tableExists(db, "ChapterCommentary") {
                if try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM ChapterCommentary WHERE Book=? AND Chapter=? LIMIT 1",
                    arguments: [book, chapter]
                ) != nil { return true }
            }
            if try tableExists(db, "BookCommentary") {
                if try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM BookCommentary WHERE Book=? LIMIT 1",
                    arguments: [book]
                ) != nil { return true }
            }
            return false
        }
    }

    // MARK: - Private helpers

    private func tableExists(_ db: Database, _ name: String) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
            SELECT 1 FROM sqlite_master
            WHERE type='table' AND name=? COLLATE NOCASE LIMIT 1
            """,
            arguments: [name]
        ) != nil
    }

    private func topicTable(_ db: Database, prefer: String) throws -> String {
        let order = prefer == "lexicon" ? ["Lexicon", "Dictionary"] : ["Dictionary", "Lexicon"]
        for t in order {
            if try tableExists(db, t) { return t }
        }
        throw ModuleError.missingTable
    }

    /// Actual column names for topic/definition in this module (case / aliases vary).
    private struct TopicSchema: Sendable {
        let table: String
        let topicCol: String
        let definitionCol: String
    }

    /// Discover Lexicon/Dictionary table + real column names via PRAGMA table_info.
    private func topicSchema(_ db: Database, prefer: String) throws -> TopicSchema? {
        let order = prefer == "lexicon" ? ["Lexicon", "Dictionary"] : ["Dictionary", "Lexicon"]
        for table in order {
            guard try tableExists(db, table) else { continue }
            // Prefer the canonical name from sqlite_master (preserves real casing)
            let resolved = try String.fetchOne(
                db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name=? COLLATE NOCASE
                LIMIT 1
                """,
                arguments: [table]
            ) ?? table
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\"\(resolved)\")")
            var names: [String] = []
            for row in rows {
                if let n = row["name"] as? String {
                    names.append(n)
                } else if let n: String = row[1] { // name is column index 1
                    names.append(n)
                }
            }
            guard !names.isEmpty else { continue }

            func pick(_ candidates: [String]) -> String? {
                for want in candidates {
                    if let hit = names.first(where: { $0.caseInsensitiveCompare(want) == .orderedSame }) {
                        return hit
                    }
                }
                return nil
            }

            // Standard e-Sword: Topic + Definition. Fallbacks for odd ports.
            guard let topicCol = pick(["Topic", "topic", "Subject", "Word", "Key", "Lemma"]),
                  let defCol = pick(["Definition", "definition", "Description", "Content", "Data", "Body", "Text"])
            else { continue }

            return TopicSchema(table: resolved, topicCol: topicCol, definitionCol: defCol)
        }
        return nil
    }

    private enum TopicMatchMode {
        /// DRAE-style lemma labels only (`lemma, …` / `lemma (…)`).
        case exact
        /// Headword starts with the query (autocomplete / incomplete typing).
        case prefix
    }

    /// Indexed equality for many accent/case probes in **one** round-trip.
    private func fetchEqualTopics(
        _ db: Database,
        schema: TopicSchema,
        topics: [String],
        limit: Int
    ) throws -> [DictEntry] {
        let unique = dedupeTopics(topics)
        guard !unique.isEmpty else { return [] }
        let t = schema.topicCol
        let d = schema.definitionCol
        let table = schema.table
        // Topic = ? COLLATE NOCASE OR … — SQLite can use TopicIndex per equality.
        let ors = unique.map { _ in "\"\(t)\" = ? COLLATE NOCASE" }.joined(separator: " OR ")
        let sql = """
        SELECT "\(t)", "\(d)" FROM "\(table)"
        WHERE \(ors)
        LIMIT ?
        """
        let args = StatementArguments(unique) + [limit]
        let rows = try Row.fetchAll(db, sql: sql, arguments: args)
        return rowsToEntries(rows, schema: schema, limit: limit)
    }

    /// Prefix LIKE for "lemma, da" / "lemma (…)" — still indexable (`query,%` has no leading %).
    private func fetchLemmaTopics(
        _ db: Database,
        schema: TopicSchema,
        probes: [String],
        limit: Int
    ) throws -> [DictEntry] {
        var seen = Set<String>()
        var out: [DictEntry] = []
        let t = schema.topicCol
        let d = schema.definitionCol
        let table = schema.table
        for q in dedupeTopics(probes) {
            let sql = """
            SELECT "\(t)", "\(d)" FROM "\(table)"
            WHERE "\(t)" LIKE ? OR "\(t)" LIKE ?
            LIMIT ?
            """
            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: ["\(q),%", "\(q) (%", limit]
            )
            for e in rowsToEntries(rows, schema: schema, limit: limit) {
                let key = e.topic.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(e)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    private func fetchPrefixTopics(
        _ db: Database,
        schema: TopicSchema,
        probes: [String],
        limit: Int
    ) throws -> [DictEntry] {
        var seen = Set<String>()
        var out: [DictEntry] = []
        let t = schema.topicCol
        let d = schema.definitionCol
        let table = schema.table
        for q in dedupeTopics(probes) {
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT "\(t)", "\(d)" FROM "\(table)"
                WHERE "\(t)" LIKE ?
                LIMIT ?
                """,
                arguments: ["\(q)%", limit]
            )
            for e in rowsToEntries(rows, schema: schema, limit: limit) {
                let key = e.topic.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(e)
                if out.count >= limit { return out }
            }
        }
        // Prefer shorter headwords when several prefix hits
        return out.sorted { $0.topic.count < $1.topic.count }
    }

    private func rowsToEntries(_ rows: [Row], schema: TopicSchema, limit: Int) -> [DictEntry] {
        var out: [DictEntry] = []
        out.reserveCapacity(min(rows.count, limit))
        for row in rows {
            let topic = cellString(row, schema.topicCol)
            let def = cellString(row, schema.definitionCol)
            guard !def.isEmpty else { continue }
            if ESwordText.looksEncrypted(def) { continue }
            let entry = Self.makeStudyEntry(topic: topic, definition: def)
            guard !entry.plain.isEmpty else { continue }
            out.append(entry)
            if out.count >= limit { break }
        }
        return out
    }

    private func dedupeTopics(_ topics: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in topics {
            let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !x.isEmpty, !seen.contains(x) else { continue }
            seen.insert(x)
            out.append(x)
        }
        return out
    }

    private func topicEqualsAny(_ db: Database, schema: TopicSchema, topics: [String]) throws -> Bool {
        let unique = dedupeTopics(topics)
        guard !unique.isEmpty else { return false }
        let t = schema.topicCol
        let ors = unique.map { _ in "\"\(t)\" = ? COLLATE NOCASE" }.joined(separator: " OR ")
        return try Row.fetchOne(
            db,
            sql: "SELECT 1 FROM \"\(schema.table)\" WHERE \(ors) LIMIT 1",
            arguments: StatementArguments(unique)
        ) != nil
    }

    /// Avoid decoding multi‑MB articles into RAM (jetsam on device).
    /// Always runs morphology strip (lexi/dict/cmt) so tags like `verb.hit.impf.p2.m.pl` never reach UI.
    private static func boundedPlain(_ def: String) -> String {
        let clipped = def.count > 120_000 ? String(def.prefix(120_000)) : def
        var plain = ESwordText.moduleFieldToPlain(clipped)
        // Defense in depth — moduleFieldToPlain already strips; keep if path changes
        plain = ESwordText.stripMorphologyNoise(plain)
        plain = plain
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if def.count > 120_000, !plain.hasSuffix("…") {
            return plain + "…"
        }
        return plain
    }

    /// Universal entry builder for **every** dictionary / lexicon module:
    /// plain text + Hebrew/Greek lemma + Latin pronunciation when present in the article.
    ///
    /// Structure is read from the **raw** field first (`LexiconArticle`), because e-Sword
    /// marks lemma / pronunciation / glosses with inline colors that flattening destroys.
    /// Plain-text scraping stays as the fallback for modules that mark nothing.
    private static func makeStudyEntry(topic: String, definition: String) -> DictEntry {
        let plain = boundedPlain(definition)
        let article = LexiconArticle.parse(definition)

        let script = article.lemma.isEmpty
            ? (StrongResolve.extractOriginalHeadwordFromLexiconPlain(plain) ?? "")
            : article.lemma
        let pron = article.pronunciation.isEmpty
            ? (StrongResolve.extractTranslitFromLexiconPlain(plain) ?? "")
            : article.pronunciation
        let glosses = article.glosses.isEmpty
            ? StrongResolve.extractSpanishGlossesFromLexiconPlain(plain)
            : article.glosses

        return DictEntry(
            topic: topic,
            plain: plain,
            html: plain,
            originalScript: script,
            pronunciation: pron,
            glosses: glosses,
            sections: article.sections,
            strongRefs: article.strongRefs
        )
    }

    private func topicExactExists(_ db: Database, schema: TopicSchema, topic: String) throws -> Bool {
        let t = schema.topicCol
        return try Row.fetchOne(
            db,
            sql: "SELECT 1 FROM \"\(schema.table)\" WHERE \"\(t)\" = ? COLLATE NOCASE LIMIT 1",
            arguments: [topic]
        ) != nil
    }

    private func topicExists(
        _ db: Database,
        schema: TopicSchema,
        query: String,
        mode: TopicMatchMode
    ) throws -> Bool {
        let t = schema.topicCol
        let table = schema.table
        switch mode {
        case .exact:
            return try Row.fetchOne(
                db,
                sql: """
                SELECT 1 FROM "\(table)"
                WHERE "\(t)" = ? COLLATE NOCASE
                   OR "\(t)" LIKE ?
                   OR "\(t)" LIKE ?
                LIMIT 1
                """,
                arguments: [query, "\(query),%", "\(query) (%"]
            ) != nil
        case .prefix:
            return try Row.fetchOne(
                db,
                sql: """
                SELECT 1 FROM "\(table)"
                WHERE "\(t)" LIKE ?
                LIMIT 1
                """,
                arguments: ["\(query)%"]
            ) != nil
        }
    }
}

// MARK: - Spanish / Strong query normalization for Bible sync

enum QueryNormalizer {
    /// Headword before DRAE-style gloss: "arbolado, da" → "arbolado", "casa (sust.)" → "casa".
    static func headword(from topic: String) -> String {
        var t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = t.firstIndex(of: ",") {
            t = String(t[..<comma])
        } else if let paren = t.firstIndex(of: "(") {
            t = String(t[..<paren])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Variants of a surface Spanish word for dictionary headword matching.
    /// Includes case/diacritic forms and light stems, plus Spanish accent expansions
    /// so an unaccented Bible token ("arbol") still exact-matches "árbol" / "ÁRBOL".
    static func dictionaryVariants(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip punctuation attached to Bible tokens
        let punct = CharacterSet.punctuationCharacters.union(.symbols)
        s = s.trimmingCharacters(in: punct)
        guard !s.isEmpty else { return [] }

        var out: [String] = []
        func push(_ x: String) {
            let t = x.trimmingCharacters(in: .whitespacesAndNewlines)
            // Exact de-dupe only. SQLite NOCASE does not fold á↔Á, so we must keep
            // both "árbol" and "ÁRBOL" as separate probe strings for ALL-CAPS modules.
            guard !t.isEmpty, !out.contains(t) else { return }
            out.append(t)
        }

        let es = Locale(identifier: "es")
        push(s)
        push(s.lowercased())
        // SQLite NOCASE only folds A–Z; accented headwords like "ÁRBOL" need explicit caps.
        push(s.uppercased(with: es))
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: es)
        push(folded)
        push(folded.uppercased(with: es))
        push(s.folding(options: .diacriticInsensitive, locale: es))

        // Light Spanish stemming heuristics (not perfect, but helps students).
        // Only keep stems that stay reasonably long so we never search "ol" / "arb".
        func pushStem(_ stem: String) {
            guard stem.count >= 3 else { return }
            push(stem)
            push(stem.uppercased(with: es))
        }
        if folded.hasSuffix("es"), folded.count > 4 { pushStem(String(folded.dropLast(2))) }
        if folded.hasSuffix("s"), folded.count > 3 { pushStem(String(folded.dropLast())) }
        if folded.hasSuffix("mente"), folded.count > 7 { pushStem(String(folded.dropLast(5))) }
        if folded.hasSuffix("ando") || folded.hasSuffix("endo"), folded.count > 5 {
            pushStem(String(folded.dropLast(4)))
        }
        if folded.hasSuffix("ado") || folded.hasSuffix("ido"), folded.count > 4 {
            pushStem(String(folded.dropLast(3)))
        }

        // Verb conjugations → stem / infinitive (deleitarás, deleitate → deleitar)
        let verbEnds = [
            "ariamos", "arias", "aria", "aremos", "areis", "aran", "aras", "ara", "are",
            "asteis", "aron", "aste", "amos", "abas", "aban", "aba",
            "iendo", "ando", "ate", "ete", "ite", "ais", "eis",
        ]
        for end in verbEnds where folded.count > end.count + 3 && folded.hasSuffix(end) {
            let stem = String(folded.dropLast(end.count))
            pushStem(stem)
            // Prefer -ar infinitive for dictionary headwords
            if stem.count >= 3 {
                pushStem(stem + "ar")
                pushStem(stem + "er")
                pushStem(stem + "ir")
            }
            break
        }
        // Light: …arás / …ará already covered; also bare …ate (imperative-ish)
        if folded.hasSuffix("ate"), folded.count > 5 {
            let stem = String(folded.dropLast(3))
            pushStem(stem)
            pushStem(stem + "ar")
        }

        // Accent expansion only on the folded form (keeps probe count small for SQL).
        for expanded in spanishAccentExpansions(folded, maxVariants: 16) {
            push(expanded)
            push(expanded.uppercased(with: es))
        }

        // Never offer morphology codes as dictionary probes
        return out.filter { !StrongResolve.isMorphologyCode($0) }
    }

    /// Prefer a human Spanish gloss over morph noise / empty.
    static func preferredSpanishHeadword(_ candidates: [String]) -> String? {
        for c in candidates {
            let t = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if StrongResolve.isPlausibleSpanishGloss(t) { return t }
        }
        return nil
    }

    /// Small set for LIKE / lemma probes — must stay tiny so badges stay snappy.
    static func primaryDictionaryProbes(_ raw: String) -> [String] {
        let all = dictionaryVariants(raw)
        // Prefer shorter unique forms (surface + folded + common stems), cap hard.
        var out: [String] = []
        var seen = Set<String>()
        for t in all.sorted(by: { $0.count < $1.count }) {
            let key = t.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(t)
            if out.count >= 6 { break }
        }
        return out
    }

    /// Expand unaccented Spanish letters into accented alternatives (bounded).
    static func spanishAccentExpansions(_ s: String, maxVariants: Int = 16) -> [String] {
        let map: [Character: [Character]] = [
            "a": ["a", "á"], "A": ["A", "Á"],
            "e": ["e", "é"], "E": ["E", "É"],
            "i": ["i", "í"], "I": ["I", "Í"],
            "o": ["o", "ó"], "O": ["O", "Ó"],
            "u": ["u", "ú", "ü"], "U": ["U", "Ú", "Ü"],
            "n": ["n", "ñ"], "N": ["N", "Ñ"],
        ]
        let chars = Array(s)
        var results: [String] = [""]
        for (idx, ch) in chars.enumerated() {
            let options = map[ch] ?? [ch]
            // If further branching would exceed the cap, keep the rest of the string as-is.
            if results.count * options.count > maxVariants {
                let remaining = String(chars[idx...])
                return results.map { $0 + remaining }
            }
            var next: [String] = []
            next.reserveCapacity(results.count * options.count)
            for prefix in results {
                for o in options {
                    next.append(prefix + String(o))
                }
            }
            results = next
        }
        return results
    }
}

// MARK: - Cell helpers (never use row[col] as Int/Bool — e-Sword stores mixed types; GRDB fatals)

private func databaseValue(_ row: Row, _ column: String) -> DatabaseValue? {
    // Row subscript for DatabaseValue is safe for missing/null/wrong-type storage
    guard row.hasColumn(column) else { return nil }
    let v: DatabaseValue = row[column]
    if v.isNull { return nil }
    return v
}

private func cellString(_ row: Row, _ column: String) -> String {
    // Column names may differ in case across modules (Topic vs topic).
    let resolved: String = {
        if row.hasColumn(column) { return column }
        // GRDB columnNames is case-sensitive; fall back to case-insensitive match.
        if let hit = row.columnNames.first(where: { $0.caseInsensitiveCompare(column) == .orderedSame }) {
            return hit
        }
        return column
    }()
    guard let v = databaseValue(row, resolved) else { return "" }
    if let data = Data.fromDatabaseValue(v) {
        return bytesToText(data)
    }
    if let s = String.fromDatabaseValue(v) {
        // Some modules return String that is actually UTF-16 mis-decoded (NUL spacing)
        if s.unicodeScalars.contains(where: { $0.value == 0 }) {
            return String(s.unicodeScalars.filter { $0.value != 0 }.map { Character($0) })
        }
        return s
    }
    if let d = Double.fromDatabaseValue(v) { return String(d) }
    if let i = Int64.fromDatabaseValue(v) { return String(i) }
    return ""
}

private func stringValue(_ row: Row, keys: [String]) -> String? {
    for k in keys {
        let s = cellString(row, k)
        if !s.isEmpty { return s }
    }
    return nil
}

/// e-Sword `Version` is often REAL "3.0", not INTEGER — must accept Double/String.
private func intValue(_ row: Row, keys: [String]) -> Int? {
    for k in keys {
        guard let v = databaseValue(row, k) else { continue }
        if let i = Int.fromDatabaseValue(v) { return i }
        if let i = Int64.fromDatabaseValue(v) { return Int(i) }
        if let d = Double.fromDatabaseValue(v) { return Int(d) }
        if let s = String.fromDatabaseValue(v) {
            if let i = Int(s) { return i }
            if let d = Double(s) { return Int(d) }
        }
    }
    return nil
}

private func boolValue(_ row: Row, keys: [String]) -> Bool? {
    for k in keys {
        guard let v = databaseValue(row, k) else { continue }
        if let b = Bool.fromDatabaseValue(v) { return b }
        if let i = Int.fromDatabaseValue(v) { return i != 0 }
        if let i = Int64.fromDatabaseValue(v) { return i != 0 }
        if let d = Double.fromDatabaseValue(v) { return d != 0 }
        if let s = String.fromDatabaseValue(v) {
            let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "y"].contains(lower) { return true }
            if ["0", "false", "no", "n"].contains(lower) { return false }
        }
    }
    return nil
}

private func bytesToText(_ data: Data) -> String {
    if data.isEmpty { return "" }
    // Prefer UTF-8 (modern e-Sword modules)
    if let s = String(data: data, encoding: .utf8), !s.contains("\u{FFFD}") {
        return s.replacingOccurrences(of: "\0", with: "")
    }
    // UTF-16 LE BOM
    if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
        if let s = String(data: data, encoding: .utf16LittleEndian) {
            return s.replacingOccurrences(of: "\0", with: "")
        }
    }
    // UTF-16 LE (common in older e-Sword blobs, even without BOM)
    if data.count >= 2, data.count % 2 == 0 {
        var u16 = [UInt16]()
        u16.reserveCapacity(data.count / 2)
        for i in stride(from: 0, to: data.count, by: 2) {
            u16.append(UInt16(data[i]) | (UInt16(data[i + 1]) << 8))
        }
        if u16.first == 0xFEFF { u16.removeFirst() }
        let s = String(utf16CodeUnits: u16, count: u16.count)
        if !s.isEmpty, !s.contains("\u{FFFD}") {
            return s.replacingOccurrences(of: "\0", with: "")
        }
    }
    // Windows-1252 (legacy Spanish/English RTF-era modules) then Latin-1
    if let s = String(data: data, encoding: .windowsCP1252) {
        return s.replacingOccurrences(of: "\0", with: "")
    }
    if let s = String(data: data, encoding: .isoLatin1) {
        return s.replacingOccurrences(of: "\0", with: "")
    }
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "")
}

enum ModuleError: LocalizedError {
    case encrypted
    case missingTable
    case notFound
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .encrypted:
            return "Este módulo parece cifrado (🔒). Use un módulo moderno .bbli/.cmti/.dcti/.lexi sin DRM."
        case .missingTable:
            return "Este módulo no tiene la tabla esperada."
        case .notFound:
            return "No se encontró el módulo."
        case .importFailed(let msg):
            return "No se pudo importar: \(msg)"
        }
    }
}
