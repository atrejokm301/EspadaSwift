import XCTest
@testable import Espada

/// Reading location is global: switching Bible/commentary versions must keep
/// the exact book/chapter/verse (e.g. NVI Gen 3:15 → LBLA stays Gen 3:15).
final class StudySessionVersionSwitchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearEspadaLocationKeys()
    }

    override func tearDown() {
        clearEspadaLocationKeys()
        super.tearDown()
    }

    private func clearEspadaLocationKeys() {
        let d = UserDefaults.standard
        [
            "espada.book", "espada.chapter", "espada.verse",
            "espada.bible", "espada.bible.filename",
            "espada.commentary", "espada.commentary.filename",
            ModulePositionMemory.storageKey
        ].forEach { d.removeObject(forKey: $0) }
    }

    /// Windows/RV1960 parity: lexicon search field is Strong-only, never Spanish.
    func testLexiconQueryFieldIsStrongNeverSpanish() {
        let session = StudySession()
        session.selectedWord = "Jehová"
        session.lexiconQueryField = ""
        session.setLexiconSearchToStrong("H3068")
        XCTAssertEqual(session.lexiconQueryField, "H3068")
        XCTAssertEqual(session.strongCode, "H3068")
        XCTAssertEqual(session.lexiconStrongForSearchBar, "H3068")
        // Spanish must stay on selectedWord, not migrate into the search field
        XCTAssertEqual(session.selectedWord, "Jehová")
        XCTAssertFalse(session.lexiconQueryField.localizedCaseInsensitiveContains("Jehov"))
        // Reject Spanish into setLexiconSearchToStrong
        let before = session.lexiconQueryField
        session.setLexiconSearchToStrong("Jehová")
        XCTAssertEqual(session.lexiconQueryField, before)
    }

    /// User scenario: in Genesis 3:15 (NVI) → switch to Biblia de las Américas
    /// (or any other version) and land on the same passage.
    func testSwitchingBibleKeepsExactPassage() {
        let session = StudySession()
        let nviPath = "/tmp/modules/NVI.bbli"
        let lblaPath = "/tmp/modules/LBLA.bbli"
        let rvrPath = "/tmp/modules/RVR1960+.bbli"

        // Start somewhere else so we know the switch is not "default home"
        session.setActiveModule(path: rvrPath, kind: .bible)
        session.goTo(book: 38, chapter: 3, verse: 1) // Zacarías 3:1

        // Study Genesis 3:15 in NVI
        session.setActiveModule(path: nviPath, kind: .bible)
        session.goTo(book: 1, chapter: 3, verse: 15)
        XCTAssertEqual(session.book, 1)
        XCTAssertEqual(session.chapter, 3)
        XCTAssertEqual(session.verse, 15)

        // Switch to LBLA — must open Genesis 3:15, not Zacarías or anything else
        session.setActiveModule(path: lblaPath, kind: .bible)
        XCTAssertEqual(session.activeBiblePath, lblaPath)
        XCTAssertEqual(session.book, 1, "Bible version switch must keep book")
        XCTAssertEqual(session.chapter, 3, "Bible version switch must keep chapter")
        XCTAssertEqual(session.verse, 15, "Bible version switch must keep verse")

        // Switch again to RVR — still Genesis 3:15 (global location)
        session.setActiveModule(path: rvrPath, kind: .bible)
        XCTAssertEqual(session.book, 1)
        XCTAssertEqual(session.chapter, 3)
        XCTAssertEqual(session.verse, 15)
    }

    func testSwitchingCommentaryKeepsPassage() {
        let session = StudySession()
        let cmtA = "/tmp/modules/MatthewHenry.cmti"
        let cmtB = "/tmp/modules/Gill.cmti"

        session.goTo(book: 1, chapter: 3, verse: 15)
        session.setActiveModule(path: cmtA, kind: .commentary)
        session.setActiveModule(path: cmtB, kind: .commentary)

        XCTAssertEqual(session.book, 1)
        XCTAssertEqual(session.chapter, 3)
        XCTAssertEqual(session.verse, 15)
    }

    func testModulePositionMemoryIgnoresLegacyPerBibleLocations() {
        // Old installs stored per-file BCV maps; decoding must not fail, and
        // those maps must not affect navigation (properties removed).
        let legacy = """
        {"bibleLocations":{"rvr1960+.bbli":{"book":38,"chapter":3,"verse":1}},\
        "commentaryLocations":{},"dictionaryQueries":{},"lexiconQueries":{},\
        "passagePickerTestament":"ot","passagePickerBook":1}
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacy, forKey: ModulePositionMemory.storageKey)

        let memory = ModulePositionMemory.load()
        XCTAssertEqual(memory.passagePickerBook, 1)
        XCTAssertEqual(memory.passagePickerTestament, "ot")

        let session = StudySession()
        session.goTo(book: 1, chapter: 3, verse: 15)
        session.setActiveModule(path: "/tmp/modules/RVR1960+.bbli", kind: .bible)
        XCTAssertEqual(session.book, 1)
        XCTAssertEqual(session.chapter, 3)
        XCTAssertEqual(session.verse, 15)
    }

    func testModulePositionMemoryFileKey() {
        XCTAssertEqual(
            ModulePositionMemory.fileKey(path: "/Library/Containers/x/NVI.bbli"),
            "nvi.bbli"
        )
        XCTAssertNil(ModulePositionMemory.fileKey(path: nil))
        XCTAssertNil(ModulePositionMemory.fileKey(path: ""))
    }

    /// Switching modules must not mutate BCV even if dictionary/lexicon restore runs.
    func testAnyModuleKindSwitchPreservesPassage() {
        let session = StudySession()
        session.goTo(book: 1, chapter: 3, verse: 15)
        session.setActiveModule(path: "/tmp/a.bbli", kind: .bible)
        session.setActiveModule(path: "/tmp/a.cmti", kind: .commentary)
        session.setActiveModule(path: "/tmp/a.dcti", kind: .dictionary)
        session.setActiveModule(path: "/tmp/a.lexi", kind: .lexicon)
        session.setActiveModule(path: "/tmp/b.bbli", kind: .bible)
        XCTAssertEqual(session.book, 1)
        XCTAssertEqual(session.chapter, 3)
        XCTAssertEqual(session.verse, 15)
    }

    /// Companion Spanish is for lexicon context only. Plain reading Bibles must never
    /// activate dual-version mode (active text + RV1960 under the verse).
    func testCompanionSpanishInactiveForPlainBible() {
        let session = StudySession()
        session.setActiveModule(path: "/tmp/modules/LBLA.bbli", kind: .bible)
        // No store → no companion path resolution; dual-read flag must stay off.
        XCTAssertFalse(session.isCompanionSpanishActive)
        XCTAssertNil(session.companionSpanish(for: 15))
    }

    func testCompanionSpanishLookupDoesNotDependOnActiveVerseUI() {
        let session = StudySession()
        // Simulate lexicon-side companion map without implying Bible dual UI.
        session.companionVerseSpanish = [16: "Porque de tal manera amó Dios al mundo…"]
        XCTAssertEqual(
            session.companionSpanish(for: 16),
            "Porque de tal manera amó Dios al mundo…"
        )
        // Still inactive until a study Bible + companion path are wired together.
        XCTAssertFalse(session.isCompanionSpanishActive)
    }
}
