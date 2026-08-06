import Foundation

/// LRU in-memory cache of decoded Bible chapters (path + book + chapter → verses).
/// Keeps chapter flips and version re-reads snappy without re-hitting SQLite + HTML clean.
final class ChapterCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let path: String
        let book: Int
        let chapter: Int
    }

    private let lock = NSLock()
    private var map: [Key: [VerseRow]] = [:]
    private var order: [Key] = []
    private var maxEntries: Int

    init(maxEntries: Int = 8) {
        self.maxEntries = max(2, maxEntries)
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return map.count
    }

    func verse(for path: String, book: Int, chapter: Int) -> [VerseRow]? {
        let key = Key(path: path, book: book, chapter: chapter)
        lock.lock(); defer { lock.unlock() }
        guard let rows = map[key] else { return nil }
        // LRU touch
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return rows
    }

    func store(_ rows: [VerseRow], path: String, book: Int, chapter: Int) {
        guard !rows.isEmpty else { return }
        let key = Key(path: path, book: book, chapter: chapter)
        lock.lock(); defer { lock.unlock() }
        if map[key] == nil {
            order.append(key)
        } else if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        map[key] = rows
        while order.count > maxEntries {
            let evict = order.removeFirst()
            map.removeValue(forKey: evict)
        }
    }

    func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        order.removeAll { $0.path == path }
        map = map.filter { $0.key.path != path }
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        map.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }

    /// Shrink under memory pressure (keep most recent only).
    func shrink(to maxKeep: Int) {
        lock.lock(); defer { lock.unlock() }
        maxEntries = max(2, maxKeep)
        while order.count > maxEntries {
            let evict = order.removeFirst()
            map.removeValue(forKey: evict)
        }
    }
}
