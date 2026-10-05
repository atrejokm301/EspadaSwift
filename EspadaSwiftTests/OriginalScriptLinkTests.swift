import XCTest
import GRDB
@testable import Espada

/// Hebrew and Greek printed inside a lexicon article should be tappable the way verse
/// references are. A lexicon lists uninflected headwords while prose uses inflected
/// forms, so the index is fed from the interlinear, which pairs every inflected run with
/// the Strong's code it carries.
final class OriginalScriptLinkTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ScriptLink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeIndex(_ verses: [(Int, Int, Int, String)]) throws -> StrongIndex {
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

    // MARK: - Normalisation

    /// Vocalised prose must fold onto the bare headword, or nothing ever matches.
    func testDiacriticsAndFinalFormsFold() {
        let n = StrongIndex.normalizeScriptForm
        XCTAssertEqual(n("רֵאשִׁית"), n("ראשית"))
        XCTAssertEqual(n("אֱלֹהִים"), n("אלהים"))
        XCTAssertEqual(n("ἀγάπη"), n("αγαπη"))
        XCTAssertEqual(n("ἠγάπησεν"), n("ηγαπησεν"))
        // Final letters are positional variants of the same consonant.
        XCTAssertEqual(n("מלך"), n("מלכ"))
        // Final sigma likewise.
        XCTAssertEqual(n("θεός"), n("θεος"))
        // Interlinear word-order digits are not part of the word.
        XCTAssertEqual(n("χαίρετε1"), n("χαίρετε"))
    }

    // MARK: - Resolution

    func testInflectedFormFromTheInterlinearResolves() throws {
        let index = try makeIndex([
            (1, 1, 1, "<heb>רֵאשִׁית</heb>2 <num>H7225</num> <blu>principio</blu>"),
            (43, 3, 16, "<grk>ἠγάπησεν3</grk> êgapêsen <num>G25</num> <blu>amó</blu>"),
        ])
        XCTAssertEqual(index.strong(forForm: "רֵאשִׁית"), "H7225")
        XCTAssertEqual(index.strong(forForm: "ראשית"), "H7225", "unvocalised prose must resolve too")
        XCTAssertEqual(index.strong(forForm: "ἠγάπησεν"), "G25")
    }

    /// Two-letter runs are declension endings (`ης`, `ον`), not words. Linking them would
    /// produce confident-looking nonsense in Tuggy and Swanson, which print them constantly.
    func testShortFragmentsAreNeverResolved() throws {
        let index = try makeIndex([
            (1, 1, 1, "<grk>ης</grk> <num>G1</num> <blu>x</blu>"),
        ])
        XCTAssertNil(index.strong(forForm: "ης"))
        XCTAssertNil(index.strong(forForm: "ον"))
        XCTAssertNil(index.strong(forForm: ""))
    }

    func testUnknownWordsResolveToNothing() throws {
        let index = try makeIndex([(1, 1, 1, "<heb>רֵאשִׁית</heb> <num>H7225</num>")])
        XCTAssertNil(index.strong(forForm: "ἀγάπη"))
        XCTAssertNil(index.strong(forForm: "corazón"))
    }

    /// When a form carries several codes, the lowest is the base lemma by convention.
    func testAmbiguousFormPicksTheLowestCode() throws {
        let index = try makeIndex([
            (1, 1, 1, "<heb>אור</heb> <num>H216</num> <blu>luz</blu>"),
            (1, 1, 2, "<heb>אור</heb> <num>H215</num> <blu>alumbrar</blu>"),
        ])
        XCTAssertEqual(index.strong(forForm: "אור"), "H215")
    }

    // MARK: - Rendering

    /// The payoff: Greek inside a Tuggy definition becomes a Strong's link.
    func testScriptRunsInProseBecomeLinks() throws {
        let index = try makeIndex([
            (43, 3, 16, "<grk>ἠγάπησεν</grk> <num>G25</num> <blu>amó</blu>"),
        ])
        let prose = "Amor. El sustantivo del cual ἠγάπησεν es el verbo."
        let links = StudyLinkParser.attributed(
            prose,
            bodyColor: .primary,
            linkColor: .accentColor,
            scriptResolver: { index.strong(forForm: $0) }
        )
        let linked = links.runs.compactMap { run -> String? in
            guard run.link != nil else { return nil }
            return String(links[run.range].characters)
        }
        XCTAssertEqual(linked, ["ἠγάπησεν"])
    }

    /// Without a resolver the parser stays pure — script is plain text, as before.
    func testNoResolverLeavesScriptUnlinked() {
        let attributed = StudyLinkParser.attributed(
            "El sustantivo ἀγάπη aquí.",
            bodyColor: .primary,
            linkColor: .accentColor
        )
        XCTAssertTrue(attributed.runs.allSatisfy { $0.link == nil })
    }

    /// Verse references must keep working alongside the new script links.
    func testVerseReferencesStillLinkWhenScriptLinkingIsOn() throws {
        let index = try makeIndex([(43, 3, 16, "<grk>ἠγάπησεν</grk> <num>G25</num>")])
        let prose = "Véase Jua 3:16 y también ἠγάπησεν."
        let attributed = StudyLinkParser.attributed(
            prose,
            bodyColor: .primary,
            linkColor: .accentColor,
            scriptResolver: { index.strong(forForm: $0) }
        )
        let linked = attributed.runs.compactMap { run -> String? in
            guard run.link != nil else { return nil }
            return String(attributed[run.range].characters)
        }
        XCTAssertTrue(linked.contains("Jua 3:16"), "\(linked)")
        XCTAssertTrue(linked.contains("ἠγάπησεν"), "\(linked)")
    }
}
