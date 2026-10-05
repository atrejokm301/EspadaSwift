import XCTest
import GRDB
@testable import Espada

/// Regression: a Spanish word glossing a grouped phrase carries several Strong's codes,
/// and taking the first one handed back the Greek article.
///
/// Real Juan 3:16 markup:
///
///     ‹ τὸν12 μονογενῆ13 › <num>G3588</num> <num>G3439</num> <blu>unigénito,</blu>
///
/// Tapping «unigénito» resolved to G3588 («the», 7 053 verses) instead of G3439
/// («unigénito», 9 verses).
@MainActor
final class ContentWordPreferenceTests: XCTestCase {

    private var tempDir: URL!
    private var store: ModuleStore!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ContentWord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ModuleStore()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func hit(_ code: String) -> StrongHit {
        StrongHit(strong: code, spanish: "unigénito", greek: "", translit: "", sourceModule: "")
    }

    /// The interlinear order is preserved when nothing can rank the codes, so a missing
    /// index never makes the result arbitrary.
    func testOrderIsUnchangedWithoutAnIndex() {
        let hits = [hit("G3588"), hit("G3439")]
        let ranked = StudySession.preferringContentWords(hits, store: nil)
        XCTAssertEqual(ranked.map(\.strong), ["G3588", "G3439"])
    }

    func testSingleHitIsUntouched() {
        let hits = [hit("G3439")]
        XCTAssertEqual(
            StudySession.preferringContentWords(hits, store: store).map(\.strong),
            ["G3439"]
        )
    }

    /// With no modules loaded the store reports zero for every code — still no reordering.
    func testUnrankableCodesKeepTheirOrder() {
        let hits = [hit("G3588"), hit("G3439"), hit("G2316")]
        XCTAssertEqual(
            StudySession.preferringContentWords(hits, store: store).map(\.strong),
            ["G3588", "G3439", "G2316"]
        )
    }
}

/// Frequency ranking itself, exercised directly against a built index — this is the part
/// that decides which code a grouped phrase resolves to.
final class ContentWordRankingTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Ranking-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Build an index where G3588 is ubiquitous and G3439 is rare, as in the real text.
    private func makeIndex() throws -> StrongIndex {
        var verses: [(Int, Int, Int, String)] = []
        for v in 1...60 {
            verses.append((40, 1, v, "<num>G3588</num> <blu>el</blu>"))
        }
        verses.append((43, 3, 16, "<num>G3588</num> <num>G3439</num> <blu>unigénito</blu>"))
        verses.append((43, 1, 14, "<num>G3439</num> <blu>unigénito</blu>"))
        verses.append((43, 3, 16, "<num>G5207</num> <blu>Hijo</blu>"))

        let biblePath = tempDir.appendingPathComponent("mini.bbli").path
        let bible = try DatabaseQueue(path: biblePath)
        try bible.write { d in
            try d.execute(sql: "CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT)")
            for (b, c, v, s) in verses {
                try d.execute(sql: "INSERT INTO Bible VALUES (?, ?, ?, ?)", arguments: [b, c, v, s])
            }
        }
        let index = try StrongIndex(url: tempDir.appendingPathComponent("index.sqlite"))
        try index.rebuild(from: .init(path: biblePath))
        return index
    }

    func testCommonArticleLosesToTheRareContentWord() throws {
        let index = try makeIndex()
        XCTAssertEqual(index.occurrenceCount(of: "G3588"), 61)
        XCTAssertEqual(index.occurrenceCount(of: "G3439"), 2)

        // The ranking rule: fewest occurrences wins.
        let ranked = ["G3588", "G3439"].sorted {
            index.occurrenceCount(of: $0) < index.occurrenceCount(of: $1)
        }
        XCTAssertEqual(ranked.first, "G3439", "the article must not win")
    }

    func testRankingGeneralisesToOtherGroupedPhrases() throws {
        let index = try makeIndex()
        let ranked = ["G3588", "G5207"].sorted {
            index.occurrenceCount(of: $0) < index.occurrenceCount(of: $1)
        }
        XCTAssertEqual(ranked.first, "G5207", "«Hijo» must resolve to Son, not the article")
    }
}
