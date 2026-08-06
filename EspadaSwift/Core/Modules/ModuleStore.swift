import Foundation
import Observation
import UIKit

/// Catalog + lazy open of e-Sword modules. Only selected modules are opened.
@Observable
final class ModuleStore {
    private(set) var modules: [ModuleInfo] = []
    private(set) var isScanning = false
    private(set) var lastError: String?
    private(set) var importProgress: Double?
    private(set) var importStatus: String?

    private var openDBs: [String: ModuleDatabase] = [:]
    private var openOrder: [String] = []
    /// Soft cap: active Bible + study modules + a few probes (drops under memory pressure).
    private var maxOpen = 8
    private let maxOpenRelaxed = 8
    private let maxOpenPressure = 3
    /// Interactive module IO (chapter / commentary / dict). Utility was starving version switches.
    private let ioQueue = DispatchQueue(label: "com.asignaciondelcielo.espada.modules", qos: .userInitiated)
    /// Protects openDBs / openOrder. All open+query paths take this lock so concurrent
    /// Task.detached lookups cannot race or evict a live DatabaseQueue (device crash).
    private let dbLock = NSLock()
    private var memoryObserver: NSObjectProtocol?

    private var metaCache: [String: CachedMeta] = [:]
    /// Decoded chapter verses (LRU). Survives flips and version re-reads of the same BCV.
    let chapterCache = ChapterCache(maxEntries: 8)

    private struct CachedMeta: Codable {
        let size: UInt64
        let mtime: TimeInterval
        let info: ModuleInfo
    }

    var modulesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("EspadaSwift/Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var cacheURL: URL {
        modulesDirectory.deletingLastPathComponent().appendingPathComponent("module-meta-cache.json")
    }

    init() {
        loadMetaCache()
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryPressure()
        }
    }

    deinit {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
    }

    /// Jetsam / low-memory: drop idle module DBs and shrink the open-cache cap.
    func handleMemoryPressure() {
        dbLock.lock()
        maxOpen = maxOpenPressure
        // Keep only the most recently used handles
        while openOrder.count > maxOpen {
            let evict = openOrder.removeFirst()
            openDBs.removeValue(forKey: evict)
        }
        dbLock.unlock()
        chapterCache.shrink(to: 2)
        clearInterlinearTokenCache()
    }

    /// After pressure eases (next chapter load / resume), allow a few more handles again.
    func relaxMemoryPressure() {
        dbLock.lock()
        maxOpen = maxOpenRelaxed
        dbLock.unlock()
    }

    // MARK: - Catalog

    /// Fast launch path: list files from disk + cache; SQLite Details only for new files.
    @MainActor
    func rescan() async {
        isScanning = true
        lastError = nil
        defer { isScanning = false }

        let dir = modulesDirectory
        let cacheSnapshot = metaCache

        do {
            let list: [ModuleInfo] = try await withCheckedThrowingContinuation { cont in
                ioQueue.async {
                    cont.resume(returning: Self.scanDirectory(dir, cache: cacheSnapshot, lightweight: true))
                }
            }
            rebuildCache(from: list, dir: dir)
            modules = Self.sorted(list)
        } catch {
            lastError = error.localizedDescription
            // Keep previous catalog rather than crash
        }
    }

    func modules(of kind: ModuleKind, includeEncrypted: Bool = false) -> [ModuleInfo] {
        modules.filter { $0.kind == kind && (includeEncrypted || !$0.encrypted) }
    }

    /// Copy preferred Spanish study Bibles from Downloads into the app library if missing.
    /// - Plain RV1960 (as-is Spanish)
    /// - Interlinear iRV 1960+ and/or RV1960+ Strong
    /// Skips entirely when the library already has any Bible (cold-start / battery).
    @MainActor
    func ensurePreferredSpanishBibles() async {
        // Device cold start: never scan huge Downloads folders if we already have Bibles.
        let bibles = modules(of: .bible)
        if !bibles.isEmpty { return }

        let wantedNames = [
            "RV1960 Reina Valera 1960.bbli",
            "AB-rv1960_reina_valera_1960.bbli",
            "00Interlineal-iRV 1960+.bbli",
            "AA-rv1960+_reina_valera_1960_con_strong.bbli",
        ]
        // Simulator / Mac-side seeds only — avoid enumerating large dirs on phone.
        #if targetEnvironment(simulator)
        let searchRoots: [URL] = [
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads"),
            URL(fileURLWithPath: "/Users/amed301/Downloads/E-Sword for Apple (3)"),
            URL(fileURLWithPath: "/Users/amed301/Downloads/E-Sword for Apple"),
        ].compactMap { $0 }
        #else
        let searchRoots: [URL] = []
        #endif

        guard !searchRoots.isEmpty else { return }

        var toImport: [URL] = []
        let existing = Set(modules.map { $0.filename.lowercased() })

        for name in wantedNames {
            if existing.contains(name.lowercased()) { continue }
            // Also match by simplified key
            let key = name.lowercased()
                .replacingOccurrences(of: " ", with: "")
            if existing.contains(where: { $0.replacingOccurrences(of: " ", with: "") == key }) {
                continue
            }
            for root in searchRoots {
                let candidate = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    toImport.append(candidate)
                    break
                }
                // Fuzzy: any file in folder matching tokens
                if let kids = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                    if let hit = kids.first(where: { url in
                        let n = url.lastPathComponent.lowercased()
                        if name.lowercased().contains("interlineal") {
                            return n.contains("interlineal") && n.contains("1960") && n.hasSuffix(".bbli")
                        }
                        if name.lowercased().contains("con_strong") || name.contains("+") {
                            return n.contains("rv1960") && n.contains("strong") && n.hasSuffix(".bbli")
                        }
                        return n.contains("rv1960") && n.contains("reina") && !n.contains("strong")
                            && !n.contains("interlineal") && n.hasSuffix(".bbli")
                    }) {
                        if !existing.contains(hit.lastPathComponent.lowercased()) {
                            toImport.append(hit)
                        }
                        break
                    }
                }
            }
        }

        guard !toImport.isEmpty else { return }
        _ = await importFiles(from: toImport)
        await rescan()
    }

    // MARK: - Import (memory-safe)

    /// Import files/folders one-by-one off the main thread. Safe for large batches.
    @MainActor
    func importFiles(from urls: [URL], progress: ((Double, String) -> Void)? = nil) async -> (ok: Int, failed: Int) {
        importProgress = 0
        importStatus = "Preparando…"
        lastError = nil

        // Security scope for picker roots (must start on this call stack)
        var rootAccessors: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                rootAccessors.append(url)
            }
        }

        defer {
            for url in rootAccessors {
                url.stopAccessingSecurityScopedResource()
            }
            importProgress = nil
            importStatus = nil
        }

        // Expand folders on background queue
        let moduleURLs: [URL] = await withCheckedContinuation { cont in
            ioQueue.async {
                cont.resume(returning: ESwordImportFilter.expandToModuleFiles(urls))
            }
        }

        guard !moduleURLs.isEmpty else {
            lastError = "No se encontraron módulos e-Sword (.bbli, .cmti, .dcti, .lexi…)."
            return (0, max(1, urls.count))
        }

        let destDir = modulesDirectory
        var ok = 0
        var failed = 0
        let total = moduleURLs.count

        for (index, url) in moduleURLs.enumerated() {
            let name = url.lastPathComponent
            importStatus = "Copiando \(index + 1)/\(total): \(name)"
            importProgress = Double(index) / Double(max(total, 1))
            progress?(importProgress ?? 0, importStatus ?? "")

            let result: Result<Void, Error> = await withCheckedContinuation { cont in
                ioQueue.async {
                    autoreleasepool {
                        let nested = url.startAccessingSecurityScopedResource()
                        defer { if nested { url.stopAccessingSecurityScopedResource() } }
                        do {
                            let dest = destDir.appendingPathComponent(name)
                            let fm = FileManager.default
                            if fm.fileExists(atPath: dest.path) {
                                try fm.removeItem(at: dest)
                            }
                            // Prefer coordinated copy for Files provider / iCloud
                            try Self.copyFileCoordinated(from: url, to: dest)
                            cont.resume(returning: .success(()))
                        } catch {
                            cont.resume(returning: .failure(error))
                        }
                    }
                }
            }

            switch result {
            case .success:
                ok += 1
            case .failure(let error):
                failed += 1
                lastError = error.localizedDescription
            }

            // Let UI + jetsam pressure recover between large files
            await Task.yield()
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
        }

        importProgress = 1
        importStatus = "Indexando catálogo…"
        await rescan()
        return (ok, failed)
    }

    @MainActor
    func importFromFolder(path: String) async -> Int {
        await importFiles(from: [URL(fileURLWithPath: path)]).ok
    }

    @MainActor
    func deleteModule(_ module: ModuleInfo) async {
        close(path: module.path)
        try? FileManager.default.removeItem(atPath: module.path)
        metaCache.removeValue(forKey: module.filename.lowercased())
        saveMetaCache()
        await rescan()
    }

    /// Wipe catalog modules (recovery). Does not delete the app.
    @MainActor
    func clearAllModules() async {
        openDBs.removeAll()
        openOrder.removeAll()
        chapterCache.removeAll()
        let dir = modulesDirectory
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        metaCache.removeAll()
        saveMetaCache()
        modules = []
    }

    // MARK: - Queries (thread-safe)

    /// Open (or reuse) a module DB. Must be called while `dbLock` is held.
    private func openDatabaseUnlocked(path: String) throws -> ModuleDatabase {
        if let existing = openDBs[path] {
            touchUnlocked(path)
            return existing
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw ModuleError.notFound
        }
        let db = try ModuleDatabase(path: path)
        openDBs[path] = db
        openOrder.append(path)
        while openOrder.count > maxOpen {
            let evict = openOrder.removeFirst()
            // Never drop the path we just opened
            if evict == path { openOrder.append(evict); break }
            openDBs.removeValue(forKey: evict)
        }
        return db
    }

    private func touchUnlocked(_ path: String) {
        if let idx = openOrder.firstIndex(of: path) {
            openOrder.remove(at: idx)
            openOrder.append(path)
        }
    }

    /// Run work against a module DB with exclusive open/evict protection.
    private func withDatabase<T>(path: String, _ body: (ModuleDatabase) throws -> T) throws -> T {
        dbLock.lock()
        defer { dbLock.unlock() }
        let db = try openDatabaseUnlocked(path: path)
        return try body(db)
    }

    /// Background-friendly wrapper (serial queue so we never hammer SQLite from many threads).
    private func onIOQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            ioQueue.async {
                autoreleasepool {
                    do {
                        cont.resume(returning: try work())
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    func loadChapter(modulePath: String, book: Int, chapter: Int) throws -> [VerseRow] {
        // Hot path: already decoded chapter still in RAM
        if let cached = chapterCache.verse(for: modulePath, book: book, chapter: chapter) {
            return cached
        }
        relaxMemoryPressure()
        let decoded = try withDatabase(path: modulePath) { db in
            let rows = try db.loadChapter(book: book, chapter: chapter)
            if let first = rows.first, ESwordText.looksEncrypted(first.scripture) {
                throw ModuleError.encrypted
            }
            // Process one verse at a time so large interlinear chapters don't peak RAM.
            // Cap decode work: interlinear HTML can be huge; full clean of every verse
            // was the main “version switch forever” cost.
            return rows.map { row in
                autoreleasepool { () -> VerseRow in
                    let raw = row.scripture
                    let plain: String
                    if raw.count > 12_000 {
                        // Keep raw for study mode / red-letter; show a truncated plain body.
                        plain = ESwordText.toPlain(
                            ESwordText.cleanToMarkers(String(raw.prefix(12_000)))
                        ) + "…"
                    } else {
                        plain = ESwordText.toPlain(ESwordText.cleanToMarkers(raw))
                    }
                    return VerseRow(verse: row.verse, raw: raw, tokens: [], plain: plain)
                }
            }
        }
        chapterCache.store(decoded, path: modulePath, book: book, chapter: chapter)
        return decoded
    }

    func loadChapterAsync(modulePath: String, book: Int, chapter: Int) async throws -> [VerseRow] {
        // Fast path on caller thread if already cached (no queue hop)
        if let cached = chapterCache.verse(for: modulePath, book: book, chapter: chapter) {
            return cached
        }
        return try await onIOQueue { try self.loadChapter(modulePath: modulePath, book: book, chapter: chapter) }
    }

    /// Warm prev/next chapters into the cache without blocking the UI (battery-friendly).
    func prefetchChapters(modulePath: String, pairs: [(book: Int, chapter: Int)]) {
        guard !pairs.isEmpty else { return }
        let need = pairs.filter { chapterCache.verse(for: modulePath, book: $0.book, chapter: $0.chapter) == nil }
        guard !need.isEmpty else { return }
        ioQueue.async { [weak self] in
            guard let self else { return }
            for pair in need {
                autoreleasepool {
                    _ = try? self.loadChapter(modulePath: modulePath, book: pair.book, chapter: pair.chapter)
                }
            }
        }
    }

    func tokenizeVerse(raw: String, verse: Int) -> [VerseToken] {
        let clipped = raw.count > 30_000 ? String(raw.prefix(30_000)) : raw
        return VerseTokenizer.tokenize(rawScripture: clipped, verse: verse)
    }

    /// Raw Scripture cell for one verse (tags preserved). Prefers chapter cache.
    func loadVerseRaw(modulePath: String, book: Int, chapter: Int, verse: Int) throws -> String? {
        if let cached = chapterCache.verse(for: modulePath, book: book, chapter: chapter),
           let row = cached.first(where: { $0.verse == verse }) {
            return row.raw
        }
        return try withDatabase(path: modulePath) { db in
            try db.loadVerse(book: book, chapter: chapter, verse: verse)
        }
    }

    func loadVerseRawAsync(modulePath: String, book: Int, chapter: Int, verse: Int) async throws -> String? {
        if let cached = chapterCache.verse(for: modulePath, book: book, chapter: chapter),
           let row = cached.first(where: { $0.verse == verse }) {
            return row.raw
        }
        return try await onIOQueue {
            try self.loadVerseRaw(modulePath: modulePath, book: book, chapter: chapter, verse: verse)
        }
    }

    /// Session cache for parsed interlinear tokens: path|book|chapter|verse → tokens.
    private var interlinearTokenCache: [String: [InterlinearToken]] = [:]
    private let interlinearTokenCacheLimit = 48

    private func interlinearCacheKey(path: String, book: Int, chapter: Int, verse: Int) -> String {
        "\(path)|\(book)|\(chapter)|\(verse)"
    }

    /// Drop interlinear parse cache (memory pressure / rescan).
    func clearInterlinearTokenCache() {
        dbLock.lock()
        interlinearTokenCache.removeAll(keepingCapacity: false)
        dbLock.unlock()
    }

    private func cachedInterlinearTokens(path: String, book: Int, chapter: Int, verse: Int) -> [InterlinearToken]? {
        dbLock.lock()
        defer { dbLock.unlock() }
        return interlinearTokenCache[interlinearCacheKey(path: path, book: book, chapter: chapter, verse: verse)]
    }

    private func storeInterlinearTokens(_ tokens: [InterlinearToken], path: String, book: Int, chapter: Int, verse: Int) {
        dbLock.lock()
        defer { dbLock.unlock() }
        if interlinearTokenCache.count >= interlinearTokenCacheLimit {
            // Drop arbitrary oldest-ish half (keys are not ordered; cheap eviction)
            let drop = interlinearTokenCache.keys.prefix(interlinearTokenCacheLimit / 2)
            for k in drop { interlinearTokenCache.removeValue(forKey: k) }
        }
        interlinearTokenCache[interlinearCacheKey(path: path, book: book, chapter: chapter, verse: verse)] = tokens
    }

    /// Resolve Spanish (or Strong) word → Strong’s + original script via interlinear modules.
    /// Runs SQLite + parse on the caller’s queue (use `resolveStrongsAsync` from UI).
    /// Strong codes reverse-lookup Spanish + Hebrew/Greek in the current verse.
    func resolveStrongs(
        bookNumber: Int,
        chapter: Int,
        verse: Int,
        word: String,
        wordIndex: Int?,
        interlinearModules: [ModuleInfo]
    ) throws -> ResolveStrongsResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStrongQuery = StrongResolve.normalizeStrong(trimmed) != nil

        // Surface forms from plain RV1960 often need folding/stems vs iRV <blu> glosses.
        // For Strong codes, probes are unused (reverse path uses the code itself).
        var probes: [String] = []
        if !isStrongQuery {
            probes = QueryNormalizer.dictionaryVariants(trimmed)
            if probes.isEmpty { probes = [trimmed] }
            if !probes.contains(where: { $0 == trimmed }) {
                probes.insert(trimmed, at: 0)
            }
        } else {
            probes = [trimmed]
        }

        let ranked = StrongResolve.rankedInterlinearModules(interlinearModules)
        guard !ranked.isEmpty else {
            return .empty(
                word: trimmed,
                note: "No hay mapa Strong (RV1960+ con números, o iRV 1960+). Impórtelo en Módulos — se usa en segundo plano mientras lee Reina Valera 1960."
            )
        }

        var lastNote = ""
        var lastPath = ""
        var lastTitle = ""

        for mod in ranked {
            let title = mod.displayName.isEmpty ? mod.filename : mod.displayName
            let path = mod.path

            let tokens: [InterlinearToken]
            if let cached = cachedInterlinearTokens(path: path, book: bookNumber, chapter: chapter, verse: verse),
               !cached.isEmpty {
                tokens = cached
            } else {
                let raw: String?
                do {
                    raw = try loadVerseRaw(modulePath: path, book: bookNumber, chapter: chapter, verse: verse)
                } catch {
                    lastNote = "No se pudo leer el versículo en \(title)."
                    lastPath = path
                    lastTitle = title
                    continue
                }

                guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    lastNote = "Versículo vacío en \(title)."
                    lastPath = path
                    lastTitle = title
                    continue
                }
                if ESwordText.looksEncrypted(raw) {
                    lastNote = "Módulo cifrado o ilegible: \(title)."
                    lastPath = path
                    lastTitle = title
                    continue
                }
                if !StrongResolve.looksLikeInterlinearScripture(raw) {
                    lastNote = "\(title) no parece un mapa Strong (iRV o RV1960+ con números)."
                    lastPath = path
                    lastTitle = title
                    continue
                }

                // iRV (<blu>) **or** RV1960+ (palabra <num>H…</num>) — both map plain RV Spanish → Strong
                tokens = StrongResolve.parseStrongsMapTokens(raw)
                if tokens.isEmpty {
                    lastNote = "\(title) no tiene pares palabra↔Strong en este versículo."
                    lastPath = path
                    lastTitle = title
                    continue
                }
                storeInterlinearTokens(tokens, path: path, book: bookNumber, chapter: chapter, verse: verse)
            }

            let result = StrongResolve.resolveFromTokens(
                word: trimmed,
                wordIndex: wordIndex,
                tokens: tokens,
                interlinearPath: path,
                interlinearTitle: title,
                wordProbes: probes
            )
            // Accept hits that have Strong and/or original script (Spanish may be empty for • glosses)
            if result.hits.contains(where: {
                StrongResolve.normalizeStrong($0.strong) != nil
                    && (StrongResolve.isPlausibleSpanishGloss($0.spanish) || !$0.greek.isEmpty)
            }) || (!result.hits.isEmpty && !isStrongQuery) {
                return result
            }
            if isStrongQuery, !result.hits.isEmpty {
                // Keep best reverse attempt (may only have original script)
                lastNote = result.note
                lastPath = path
                lastTitle = title
                // Prefer returning original script even without Spanish
                if result.hits.contains(where: { !$0.greek.isEmpty }) {
                    return result
                }
            } else if !result.hits.isEmpty {
                return result
            }
            lastNote = result.note
            lastPath = path
            lastTitle = title
        }

        if isStrongQuery, let direct = StrongResolve.resolveDirectStrong(trimmed) {
            var d = direct
            d.interlinearPath = lastPath
            d.interlinearTitle = lastTitle
            d.note = lastNote.isEmpty ? d.note : lastNote
            return d
        }

        return ResolveStrongsResult(
            word: trimmed,
            hits: [],
            interlinearPath: lastPath,
            interlinearTitle: lastTitle,
            note: lastNote.isEmpty
                ? "«\(trimmed)» no aparece en el interlineal de este versículo. Toque otra palabra de contenido (p. ej. amó, Dios, mundo)."
                : lastNote
        )
    }

    /// Async resolve off main thread.
    func resolveStrongsAsync(
        bookNumber: Int,
        chapter: Int,
        verse: Int,
        word: String,
        wordIndex: Int?,
        interlinearModules: [ModuleInfo]
    ) async throws -> ResolveStrongsResult {
        try await onIOQueue {
            try self.resolveStrongs(
                bookNumber: bookNumber,
                chapter: chapter,
                verse: verse,
                word: word,
                wordIndex: wordIndex,
                interlinearModules: interlinearModules
            )
        }
    }

    func loadCommentary(
        modulePath: String,
        book: Int,
        chapter: Int,
        verse: Int,
        verseScope: Bool,
        chapterScope: Bool,
        bookScope: Bool
    ) throws -> [StudyEntry] {
        try withDatabase(path: modulePath) { db in
            try db.loadCommentary(
                book: book,
                chapter: chapter,
                verse: verse,
                includeVerse: verseScope,
                includeChapter: chapterScope,
                includeBook: bookScope
            )
        }
    }

    func loadCommentaryAsync(
        modulePath: String,
        book: Int,
        chapter: Int,
        verse: Int,
        verseScope: Bool,
        chapterScope: Bool,
        bookScope: Bool
    ) async throws -> [StudyEntry] {
        try await onIOQueue {
            try self.loadCommentary(
                modulePath: modulePath,
                book: book, chapter: chapter, verse: verse,
                verseScope: verseScope, chapterScope: chapterScope, bookScope: bookScope
            )
        }
    }

    func lookupDictionary(modulePath: String, query: String) throws -> [DictEntry] {
        try withDatabase(path: modulePath) { try $0.dictionaryLookup(query: query) }
    }

    func lookupDictionaryAsync(modulePath: String, query: String) async throws -> [DictEntry] {
        try await onIOQueue { try self.lookupDictionary(modulePath: modulePath, query: query) }
    }

    func lookupLexicon(modulePath: String, strong: String) throws -> DictEntry? {
        try withDatabase(path: modulePath) { try $0.lexiconLookup(strong: strong) }
    }

    func lookupLexiconAsync(modulePath: String, strong: String) async throws -> DictEntry? {
        try await onIOQueue { try self.lookupLexicon(modulePath: modulePath, strong: strong) }
    }

    /// Probe which modules have content for the current study context (for dropdown badges).
    func probeAvailability(
        kind: ModuleKind,
        paths: [String],
        book: Int,
        chapter: Int,
        verse: Int,
        query: String
    ) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for path in paths {
            autoreleasepool {
                do {
                    map[path] = try withDatabase(path: path) { db in
                        switch kind {
                        case .commentary:
                            return try db.hasCommentaryHit(book: book, chapter: chapter, verse: verse)
                        case .dictionary:
                            return query.isEmpty ? false : (try db.hasDictionaryHit(query: query))
                        case .lexicon:
                            return query.isEmpty ? false : (try db.hasLexiconHit(query: query))
                        case .bible, .reference:
                            return false
                        }
                    }
                } catch {
                    map[path] = false
                }
            }
        }
        return map
    }

    func probeAvailabilityAsync(
        kind: ModuleKind,
        paths: [String],
        book: Int,
        chapter: Int,
        verse: Int,
        query: String
    ) async -> [String: Bool] {
        (try? await onIOQueue {
            self.probeAvailability(
                kind: kind, paths: paths,
                book: book, chapter: chapter, verse: verse, query: query
            )
        }) ?? [:]
    }

    // MARK: - Private

    private static func copyFileCoordinated(from src: URL, to dest: URL) throws {
        var coordError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: src, options: [], writingItemAt: dest, options: .forReplacing, error: &coordError) { readURL, writeURL in
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: writeURL.path) {
                    try fm.removeItem(at: writeURL)
                }
                try fm.copyItem(at: readURL, to: writeURL)
            } catch {
                copyError = error
            }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
    }

    private func touch(_ path: String) {
        openOrder.removeAll { $0 == path }
        openOrder.append(path)
    }

    private func close(path: String) {
        openDBs.removeValue(forKey: path)
        openOrder.removeAll { $0 == path }
        chapterCache.remove(path: path)
    }

    private func loadMetaCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: CachedMeta].self, from: data) else {
            return
        }
        metaCache = decoded
    }

    private func saveMetaCache() {
        guard let data = try? JSONEncoder().encode(metaCache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func rebuildCache(from list: [ModuleInfo], dir: URL) {
        var next: [String: CachedMeta] = [:]
        let fm = FileManager.default
        for info in list {
            let key = info.filename.lowercased()
            let path = dir.appendingPathComponent(info.filename).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? UInt64,
                  let mdate = attrs[.modificationDate] as? Date else { continue }
            next[key] = CachedMeta(size: size, mtime: mdate.timeIntervalSince1970, info: info)
        }
        metaCache = next
        saveMetaCache()
    }

    private static func sorted(_ list: [ModuleInfo]) -> [ModuleInfo] {
        list.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.abbreviation.localizedCaseInsensitiveCompare($1.abbreviation) == .orderedAscending
        }
    }

    /// Catalog scan. `lightweight` skips heavy sample reads for huge files.
    private static func scanDirectory(_ dir: URL, cache: [String: CachedMeta], lightweight: Bool) -> [ModuleInfo] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var result: [ModuleInfo] = []
        result.reserveCapacity(names.count)

        for name in names {
            autoreleasepool {
                let ext = (name as NSString).pathExtension
                guard let kind = ModuleKind.from(fileExtension: ext) else { return }
                let path = dir.appendingPathComponent(name).path
                let key = name.lowercased()

                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? UInt64) ?? 0
                let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

                if let cached = cache[key],
                   cached.size == size,
                   abs(cached.mtime - mtime) < 1 {
                    let info = ModuleInfo(
                        path: path,
                        filename: cached.info.filename,
                        title: cached.info.title,
                        abbreviation: cached.info.abbreviation,
                        kind: cached.info.kind,
                        encrypted: cached.info.encrypted,
                        hasStrongs: cached.info.hasStrongs,
                        version: cached.info.version
                    )
                    result.append(info)
                    return
                }

                var title = name
                var abbr = (name as NSString).deletingPathExtension
                var version = 0
                var hasStrongs = kind == .lexicon
                var encrypted = ModuleKind.isLegacyEncryptedExtension(ext)

                // Huge files: only open Details; skip sample to avoid jetsam
                let skipSample = lightweight && size > 40_000_000 // ~40 MB

                do {
                    let db = try ModuleDatabase(path: path)
                    let details = try db.readDetails()
                    if !details.title.isEmpty { title = details.title }
                    if !details.abbreviation.isEmpty { abbr = details.abbreviation }
                    version = details.version
                    hasStrongs = hasStrongs || details.strongs
                    if !encrypted && !skipSample {
                        let sample = try db.sampleText(kind: kind)
                        encrypted = ESwordText.looksEncrypted(sample)
                        if kind == .bible, !hasStrongs {
                            hasStrongs = sample.range(
                                of: #"[HG]\d{1,5}"#,
                                options: .regularExpression
                            ) != nil
                        }
                    } else if kind == .bible {
                        // Prefer Strong for known interlinear names without sampling
                        let hay = (title + abbr + name).lowercased()
                        if hay.contains("strong") || hay.contains("interlineal") || hay.contains("irv") {
                            hasStrongs = true
                        }
                    }
                    // db deallocated here — connection closed
                } catch {
                    encrypted = true
                }

                result.append(ModuleInfo(
                    path: path,
                    filename: name,
                    title: title,
                    abbreviation: abbr,
                    kind: kind,
                    encrypted: encrypted,
                    hasStrongs: hasStrongs,
                    version: version
                ))
            }
        }
        return result
    }
}
