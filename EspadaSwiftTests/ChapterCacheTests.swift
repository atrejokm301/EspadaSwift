import XCTest
@testable import Espada

final class ChapterCacheTests: XCTestCase {
    private func rows(_ n: Int) -> [VerseRow] {
        (1...n).map { VerseRow(verse: $0, raw: "r\($0)", tokens: [], plain: "p\($0)") }
    }

    func testLRUStoresAndReturns() {
        let cache = ChapterCache(maxEntries: 3)
        let path = "/tmp/nvi.bbli"
        cache.store(rows(3), path: path, book: 1, chapter: 1)
        XCTAssertEqual(cache.verse(for: path, book: 1, chapter: 1)?.count, 3)
        XCTAssertNil(cache.verse(for: path, book: 1, chapter: 2))
    }

    func testLRUEvictsOldest() {
        let cache = ChapterCache(maxEntries: 2)
        let path = "/tmp/rvr.bbli"
        cache.store(rows(1), path: path, book: 1, chapter: 1)
        cache.store(rows(1), path: path, book: 1, chapter: 2)
        cache.store(rows(1), path: path, book: 1, chapter: 3)
        // chapter 1 should be gone
        XCTAssertNil(cache.verse(for: path, book: 1, chapter: 1))
        XCTAssertNotNil(cache.verse(for: path, book: 1, chapter: 2))
        XCTAssertNotNil(cache.verse(for: path, book: 1, chapter: 3))
    }

    func testTouchKeepsHotEntry() {
        let cache = ChapterCache(maxEntries: 2)
        let path = "/tmp/lbla.bbli"
        cache.store(rows(1), path: path, book: 1, chapter: 1)
        cache.store(rows(1), path: path, book: 1, chapter: 2)
        // Touch ch1 so ch2 is oldest
        _ = cache.verse(for: path, book: 1, chapter: 1)
        cache.store(rows(1), path: path, book: 1, chapter: 3)
        XCTAssertNotNil(cache.verse(for: path, book: 1, chapter: 1))
        XCTAssertNil(cache.verse(for: path, book: 1, chapter: 2))
        XCTAssertNotNil(cache.verse(for: path, book: 1, chapter: 3))
    }

    func testRemovePathAndShrink() {
        let cache = ChapterCache(maxEntries: 8)
        cache.store(rows(1), path: "/a.bbli", book: 1, chapter: 1)
        cache.store(rows(1), path: "/b.bbli", book: 1, chapter: 1)
        cache.remove(path: "/a.bbli")
        XCTAssertNil(cache.verse(for: "/a.bbli", book: 1, chapter: 1))
        XCTAssertNotNil(cache.verse(for: "/b.bbli", book: 1, chapter: 1))
        cache.shrink(to: 1)
        XCTAssertEqual(cache.count, 1)
    }

    func testKeysDifferByModulePath() {
        let cache = ChapterCache(maxEntries: 4)
        cache.store(rows(5), path: "/nvi.bbli", book: 1, chapter: 3)
        cache.store(rows(7), path: "/rvr.bbli", book: 1, chapter: 3)
        XCTAssertEqual(cache.verse(for: "/nvi.bbli", book: 1, chapter: 3)?.count, 5)
        XCTAssertEqual(cache.verse(for: "/rvr.bbli", book: 1, chapter: 3)?.count, 7)
    }
}
