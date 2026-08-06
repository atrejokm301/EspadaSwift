import XCTest
@testable import Espada

final class RecentVersesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "espada.recentVerses")
        [
            "espada.book", "espada.chapter", "espada.verse",
            "espada.bible", "espada.bible.filename",
            "espada.crossReference", "espada.crossReference.filename"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    func testTracksLastTenDistinctVersesMostRecentFirst() {
        let session = StudySession()
        // init seeds current location once
        let seedCount = session.recentVerses.count
        XCTAssertGreaterThanOrEqual(seedCount, 1)

        for i in 1...12 {
            session.trackRecentVerse(book: 1, chapter: 1, verse: i)
        }
        XCTAssertEqual(session.recentVerses.count, StudySession.recentVersesLimit)
        XCTAssertEqual(session.recentVerses.first?.verse, 12)
        XCTAssertEqual(session.recentVerses.last?.verse, 3) // 12…3 = 10 entries
        // Dedup: revisiting verse 5 moves it to front, no duplicate
        session.trackRecentVerse(book: 1, chapter: 1, verse: 5)
        XCTAssertEqual(session.recentVerses.first?.verse, 5)
        XCTAssertEqual(session.recentVerses.filter { $0.verse == 5 }.count, 1)
        XCTAssertEqual(session.recentVerses.count, StudySession.recentVersesLimit)
    }

    func testGoToRecordsRecentVerse() {
        let session = StudySession()
        session.goTo(book: 19, chapter: 23, verse: 1)
        XCTAssertEqual(session.recentVerses.first?.book, 19)
        XCTAssertEqual(session.recentVerses.first?.chapter, 23)
        XCTAssertEqual(session.recentVerses.first?.verse, 1)
        XCTAssertEqual(session.recentVerses.first?.label, "Salmos 23:1")
    }

    func testCrossReferenceModuleHeuristic() {
        let tsk = ModuleInfo(
            path: "/tmp/tske_v12.cmti",
            filename: "tske_v12.cmti",
            title: "Treasury of Scripture Knowledge Enhanced",
            abbreviation: "TSKe",
            kind: .commentary,
            encrypted: false,
            hasStrongs: false,
            version: 3
        )
        let plain = ModuleInfo(
            path: "/tmp/MatthewHenry.cmti",
            filename: "MatthewHenry.cmti",
            title: "Matthew Henry Commentary",
            abbreviation: "MH",
            kind: .commentary,
            encrypted: false,
            hasStrongs: false,
            version: 3
        )
        let bible = ModuleInfo(
            path: "/tmp/NVI.bbli",
            filename: "NVI.bbli",
            title: "NVI",
            abbreviation: "NVI",
            kind: .bible,
            encrypted: false,
            hasStrongs: false,
            version: 3
        )
        XCTAssertTrue(tsk.isCrossReferenceModule)
        XCTAssertFalse(plain.isCrossReferenceModule)
        XCTAssertFalse(bible.isCrossReferenceModule)
    }

    func testRecentVerseLabel() {
        let r = RecentVerse(book: 43, chapter: 3, verse: 16)
        XCTAssertEqual(r.label, "Juan 3:16")
        XCTAssertEqual(r.id, "43:3:16")
    }
}
