import Foundation

/// One entry in the “últimos 10 versículos” history.
struct RecentVerse: Codable, Hashable, Identifiable, Sendable {
    var book: Int
    var chapter: Int
    var verse: Int
    /// Unix seconds when this location was visited (most recent first).
    var visitedAt: TimeInterval

    var id: String { "\(book):\(chapter):\(verse)" }

    var label: String {
        BibleBooks.reference(book: book, chapter: chapter, verse: verse)
    }

    init(book: Int, chapter: Int, verse: Int, visitedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.visitedAt = visitedAt
    }
}

extension ModuleInfo {
    /// Heuristic: commentaries that are cross-reference tools (TSK, Torrey, Spanish refs…).
    /// True cross-ref modules are usually `.cmti` with dense `<ref>` chains per verse.
    ///
    /// Only `.commentary` modules match — Strong / word concordances as `.dcti`
    /// stay in Diccionarios (e.g. "Nueva Concordancia Strong Exhaustiva").
    var isCrossReferenceModule: Bool {
        guard kind == .commentary else { return false }
        let hay = (title + " " + abbreviation + " " + filename).lowercased()
        let keys = [
            "tsk", "tske", "torrey",
            "cross ref", "crossref", "cross-ref",
            "cross_reference", "crossreferences", "x-ref", "xref",
            "parallel passage", "treasury of scripture",
            "referencias cruzadas", "referencia cruzada",
            "pasajes paralelos",
            "referencias", "referencia",
            "concordancia", "concordance",
        ]
        return keys.contains { hay.contains($0) }
    }
}
