import XCTest
import GRDB
@testable import Espada

/// The reverse index answers "where else is this word used?" — a question the app could
/// not previously ask, because scanning the interlinear for one code took ~1 900 ms.
final class StrongIndexTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StrongIndexTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Build a miniature interlinear in the real e-Sword shape.
    private func makeBible(_ verses: [(Int, Int, Int, String)]) throws -> String {
        let path = tempDir.appendingPathComponent("mini.bbli").path
        let db = try DatabaseQueue(path: path)
        try db.write { d in
            try d.execute(sql: "CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT)")
            for (b, c, v, s) in verses {
                try d.execute(
                    sql: "INSERT INTO Bible VALUES (?, ?, ?, ?)",
                    arguments: [b, c, v, s]
                )
            }
        }
        return path
    }

    private func makeIndex() throws -> StrongIndex {
        try StrongIndex(url: tempDir.appendingPathComponent("index.sqlite"))
    }

    // MARK: - Building

    func testBuildExtractsEveryCodePerVerse() throws {
        let bible = try makeBible([
            (1, 1, 1, "<heb>בְּ</heb> <num>H7225</num> <blu>principio</blu> <num>H430</num> <blu>Dios</blu>"),
            (1, 1, 2, "<num>H776</num> <blu>tierra</blu>"),
            (43, 3, 16, "<grk>ἠγάπησεν</grk> <num>G25</num> <blu>amó</blu> <num>G2316</num> <blu>Dios</blu>"),
        ])
        let index = try makeIndex()
        let rows = try index.rebuild(from: .init(path: bible))

        XCTAssertEqual(rows, 5)
        XCTAssertEqual(index.occurrenceCount(of: "H430"), 1)
        XCTAssertEqual(index.occurrences(of: "H430").first,
                       StrongIndex.Occurrence(book: 1, chapter: 1, verse: 1))
        XCTAssertEqual(index.occurrenceCount(of: "G2316"), 1)
    }

    /// The same code twice in one verse is one occurrence — a concordance lists passages.
    func testRepeatedCodeInOneVerseCountsOnce() throws {
        let bible = try makeBible([
            (1, 1, 1, "<num>H853</num> <blu>•</blu> <num>H853</num> <blu>•</blu> <num>H430</num> <blu>Dios</blu>"),
        ])
        let index = try makeIndex()
        XCTAssertEqual(try index.rebuild(from: .init(path: bible)), 2)
        XCTAssertEqual(index.occurrenceCount(of: "H853"), 1)
    }

    /// Zero-padded and spaced forms in the wild must land on the same code.
    func testCodeVariantsNormaliseToOneEntry() throws {
        let bible = try makeBible([
            (1, 1, 1, "<num>H0430</num> <blu>Dios</blu>"),
            (1, 1, 2, "<num>H 430</num> <blu>Dios</blu>"),
            (1, 1, 3, "<num>h430</num> <blu>Dios</blu>"),
        ])
        let index = try makeIndex()
        try index.rebuild(from: .init(path: bible))
        XCTAssertEqual(index.occurrenceCount(of: "H430"), 3)
        XCTAssertEqual(index.occurrenceCount(of: "H0430"), 3, "lookup must normalise too")
    }

    // MARK: - Queries

    func testOccurrencesComeBackInCanonicalOrder() throws {
        let bible = try makeBible([
            (43, 3, 16, "<num>H1</num>"),
            (1, 1, 1, "<num>H1</num>"),
            (1, 2, 1, "<num>H1</num>"),
            (1, 1, 5, "<num>H1</num>"),
        ])
        let index = try makeIndex()
        try index.rebuild(from: .init(path: bible))
        XCTAssertEqual(
            index.occurrences(of: "H1").map { "\($0.book):\($0.chapter):\($0.verse)" },
            ["1:1:1", "1:1:5", "1:2:1", "43:3:16"]
        )
    }

    func testLimitCapsTheListButNotTheCount() throws {
        let verses = (1...50).map { (1, 1, $0, "<num>H1</num>") }
        let bible = try makeBible(verses)
        let index = try makeIndex()
        try index.rebuild(from: .init(path: bible))
        XCTAssertEqual(index.occurrences(of: "H1", limit: 10).count, 10)
        XCTAssertEqual(index.occurrenceCount(of: "H1"), 50)
    }

    func testCodesInOneVerse() throws {
        let bible = try makeBible([
            (43, 3, 16, "<num>G25</num> <num>G2316</num> <num>G2889</num>"),
            (43, 3, 17, "<num>G2889</num>"),
        ])
        let index = try makeIndex()
        try index.rebuild(from: .init(path: bible))
        XCTAssertEqual(index.codes(inBook: 43, chapter: 3, verse: 16), ["G2316", "G25", "G2889"])
        XCTAssertEqual(index.codes(inBook: 43, chapter: 3, verse: 17), ["G2889"])
        XCTAssertTrue(index.codes(inBook: 99, chapter: 1, verse: 1).isEmpty)
    }

    func testUnknownAndMalformedCodesReturnNothing() throws {
        let bible = try makeBible([(1, 1, 1, "<num>H430</num>")])
        let index = try makeIndex()
        try index.rebuild(from: .init(path: bible))
        XCTAssertTrue(index.occurrences(of: "H9999").isEmpty)
        XCTAssertEqual(index.occurrenceCount(of: "H9999"), 0)
        XCTAssertTrue(index.occurrences(of: "corazón").isEmpty)
        XCTAssertTrue(index.occurrences(of: "").isEmpty)
    }

    // MARK: - Freshness

    func testIndexReportsCurrentOnlyAfterBuilding() throws {
        let bible = try makeBible([(1, 1, 1, "<num>H430</num>")])
        let source = StrongIndex.Source(path: bible)
        let index = try makeIndex()
        XCTAssertFalse(index.isCurrent(for: source))
        try index.rebuild(from: source)
        XCTAssertTrue(index.isCurrent(for: source))
    }

    /// A different interlinear must not be answered from the old index.
    func testSwitchingSourceInvalidatesTheIndex() throws {
        let first = try makeBible([(1, 1, 1, "<num>H430</num>")])
        let index = try makeIndex()
        try index.rebuild(from: .init(path: first))

        let second = tempDir.appendingPathComponent("other.bbli").path
        let db = try DatabaseQueue(path: second)
        try db.write { d in
            try d.execute(sql: "CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT)")
            try d.execute(sql: "INSERT INTO Bible VALUES (1, 1, 1, '<num>H1</num>')")
        }
        XCTAssertFalse(index.isCurrent(for: .init(path: second)))
    }

    /// Rebuilding replaces rather than accumulates.
    func testRebuildDoesNotDuplicateRows() throws {
        let bible = try makeBible([(1, 1, 1, "<num>H430</num> <num>H776</num>")])
        let index = try makeIndex()
        try index.rebuild(from: .init(path: bible))
        try index.rebuild(from: .init(path: bible))
        XCTAssertEqual(index.occurrenceCount, 2)
        XCTAssertEqual(index.occurrenceCount(of: "H430"), 1)
    }

    /// The index outlives the process — that is the whole point of persisting it.
    func testIndexSurvivesReopen() throws {
        let bible = try makeBible([(1, 1, 1, "<num>H430</num>")])
        let url = tempDir.appendingPathComponent("index.sqlite")
        let source = StrongIndex.Source(path: bible)
        try StrongIndex(url: url).rebuild(from: source)

        let reopened = try StrongIndex(url: url)
        XCTAssertTrue(reopened.isCurrent(for: source))
        XCTAssertEqual(reopened.occurrenceCount(of: "H430"), 1)
    }

    // MARK: - Edge cases

    func testEmptyAndTaglessBibleBuildsCleanly() throws {
        let bible = try makeBible([
            (1, 1, 1, ""),
            (1, 1, 2, "En el principio creó Dios los cielos y la tierra."),
        ])
        let index = try makeIndex()
        XCTAssertEqual(try index.rebuild(from: .init(path: bible)), 0)
        XCTAssertEqual(index.occurrenceCount, 0)
    }

    func testProgressReachesCompletion() throws {
        let bible = try makeBible((1...100).map { (1, 1, $0, "<num>H\($0)</num>") })
        let index = try makeIndex()
        var last: Double = -1
        try index.rebuild(from: .init(path: bible)) { last = $0 }
        XCTAssertEqual(last, 1, accuracy: 0.0001)
    }
}
