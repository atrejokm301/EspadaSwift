import XCTest
@testable import Espada

/// Every sample here is a verbatim excerpt from the module library on disk
/// (`~/Downloads/for mac espada`), taken during a full audit of all 130 modules.
final class ModuleTextRepairTests: XCTestCase {

    override func tearDown() {
        ModuleTextRepair.repairsCodepageWedges = true   // restore the shipping default
        super.tearDown()
    }

    // MARK: - Private-use glyphs

    /// `01Reina1569.bbli` / `R1569-D…bbli` — U+E003 is a `ct` ligature from the
    /// publisher's font. Untreated it renders as an empty box on iOS.
    func testCtLigatureIsExpanded() {
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("y \u{E003}ansan\u{E003}ificólo"),
            "y ctansanctificólo"
        )
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("perfe\u{E003}o"),
            "perfecto"
        )
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("Ie\u{E003}an"),
            "Iectan"
        )
    }

    /// `01ReinaValera1602.bbli` — U+E000 abbreviates *que*, so it needs a word boundary
    /// after it. `por\u{E000}es` is "porque es", never "porquees".
    func testQueAbbreviationGetsAWordBoundary() {
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("por\u{E000}es precio de ſangre"),
            "porque es precio de ſangre"
        )
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("para\u{E000}llevaße"),
            "paraque llevaße"
        )
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("\u{E000}nada aprovechava"),
            "que nada aprovechava"
        )
        // No spurious space when punctuation or whitespace already follows
        XCTAssertEqual(ModuleTextRepair.expandPrivateUseCharacters("\u{E000} ſe"), "que ſe")
    }

    /// Broken Chávez / Keil-Delitzsch — U+F895 is `ü` (`ling\u{F895}ística`).
    func testDiaeresisGlyphIsExpanded() {
        XCTAssertEqual(
            ModuleTextRepair.expandPrivateUseCharacters("ling\u{F895}ística"),
            "lingüística"
        )
    }

    /// An unmapped private-use glyph has no known text — showing tofu is worse than
    /// showing nothing.
    func testUnmappedPrivateUseIsDropped() {
        XCTAssertEqual(ModuleTextRepair.expandPrivateUseCharacters("a\u{E123}b"), "ab")
    }

    // MARK: - Mojibake

    /// `Biblia Latinoamerica 1995.cmti` — UTF-8 read as Latin-1.
    func testMojibakeIsRepaired() {
        XCTAssertEqual(ModuleTextRepair.repairMojibake("*1CrÃ³n 2:16"), "*1Crón 2:16")
        XCTAssertEqual(ModuleTextRepair.repairMojibake("Â¡Oh!"), "¡Oh!")
        XCTAssertEqual(ModuleTextRepair.repairMojibake("EspaÃ±a niÃ±o"), "España niño")
    }

    /// Three-character punctuation forms need the CP1252 round-trip: `â€™` is `E2 80 99`,
    /// but `€` is U+20AC — treating the characters as Latin-1 values would miss it.
    func testSmartPunctuationMojibakeIsRepaired() {
        XCTAssertEqual(ModuleTextRepair.repairMojibake("donâ€™t"), "don’t")
        XCTAssertEqual(ModuleTextRepair.repairMojibake("â€œcitaâ€\u{009D}"), "“cita”")
        XCTAssertEqual(ModuleTextRepair.repairMojibake("aÃ±o â€“ 1569"), "año – 1569")
    }

    /// Words that legitimately contain these letters must survive.
    func testWordsContainingLeadCharactersAreNotDamaged() {
        for text in ["Â", "â", "Ã", "cabaña Â solo", "âme", "Ãkerman"] {
            XCTAssertEqual(ModuleTextRepair.repairMojibake(text), text, text)
        }
    }

    /// Damaged rows mix good and bad text — the good half must survive untouched.
    func testMojibakeRepairKeepsCorrectTextInTheSameRow() {
        let raw = "[.] Este capítulo se repite en *1CrÃ³n 18:1"
        XCTAssertEqual(
            ModuleTextRepair.repairMojibake(raw),
            "[.] Este capítulo se repite en *1Crón 18:1"
        )
    }

    func testCleanSpanishIsNotAltered() {
        let clean = "Deléitate asimismo en Jehová; también en el corazón, ¿no conozco? niño"
        XCTAssertEqual(ModuleTextRepair.repairMojibake(clean), clean)
        XCTAssertEqual(ModuleTextRepair.sanitize(clean), clean)
    }

    // MARK: - Dead characters

    func testC1ControlsAndReplacementCharsAreDropped() {
        XCTAssertEqual(
            ModuleTextRepair.dropUnusableCharacters("texto de B \u{0081} en la mayoría"),
            "texto de B  en la mayoría"
        )
        XCTAssertEqual(ModuleTextRepair.dropUnusableCharacters("a\u{FFFD}b"), "ab")
    }

    // MARK: - Codepage wedges (opt-in)

    func testWedgeRepairIsOnByDefaultAndReachesTheFullPipeline() {
        XCTAssertTrue(ModuleTextRepair.repairsCodepageWedges)
        XCTAssertEqual(ModuleTextRepair.sanitize("se utiliza tambiιn en espaρol"),
                       "se utiliza también en español")
        XCTAssertEqual(ESwordText.moduleFieldToPlain("<p>alfabeto en espaρol</p>"),
                       "alfabeto en español")
    }

    func testWedgeRepairCanBeTurnedOff() {
        ModuleTextRepair.repairsCodepageWedges = false
        XCTAssertEqual(ModuleTextRepair.sanitize("tambiιn"), "tambiιn")
    }

    /// Greek CP1253 wedges — real Swanson / Tuggy / Pikaza / Keil text.
    func testGreekCodepageWedgesAreRepaired() {
        ModuleTextRepair.repairsCodepageWedges = true
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("tambiιn"), "también")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("espaρol"), "español")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("tνtulo"), "título")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("Mσdulo"), "Módulo")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("estα"), "está")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("Sφhne"), "Söhne")
        // Swanson G25's stored pronunciation, which the lexicon parser currently refuses
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("(agapaτ):"), "(agapaô):")
    }

    /// Hebrew CP1255 wedges — real broken-Chávez text.
    func testHebrewCodepageWedgesAreRepaired() {
        ModuleTextRepair.repairsCodepageWedges = true
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("informaciףn"), "información")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("pבgina"), "página")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("enseסanza"), "enseñanza")
        XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("fonיtica"), "fonética")
    }

    /// The whole point of the adjacency rule: genuine lemmas must be untouchable.
    func testGenuineHebrewAndGreekAreNeverRewritten() {
        ModuleTextRepair.repairsCodepageWedges = true
        for lemma in ["ἀγάπη", "לֵב", "אֱלֹהִים", "ἠγάπησεν", "θεός", "χαίρετε"] {
            XCTAssertEqual(ModuleTextRepair.repairCodepageWedges(lemma), lemma)
            XCTAssertEqual(ModuleTextRepair.repairCodepageWedges("El término \(lemma) aquí"), "El término \(lemma) aquí")
        }
        // A single Greek letter used as a heading is separated by spaces, not wedged.
        XCTAssertEqual(
            ModuleTextRepair.repairCodepageWedges("Swanson 1 α (a): alfabeto"),
            "Swanson 1 α (a): alfabeto"
        )
    }

    /// Harrison's phonetic schwa and other legitimate scripts are outside the tables.
    func testLegitimateNonLatinScriptsAreLeftAlone() {
        ModuleTextRepair.repairsCodepageWedges = true
        for text in ["bәliyyaʿal", "ܐ acróstico", "( م + ه + م = 4 )"] {
            XCTAssertEqual(ModuleTextRepair.repairCodepageWedges(text), text)
            XCTAssertEqual(ModuleTextRepair.sanitize(text), text)
        }
    }

    // MARK: - Pipeline integration

    /// Reina 1569 stores the ligature as the entity `&#xE003;`, so repair has to run
    /// after entity decoding, not before.
    func testEntityEncodedPrivateUseIsRepairedThroughTheFullPipeline() {
        let raw = "<p>y &#xE003;ansan&#xE003;ific&oacute;lo, por que enel repo&#x017F;&oacute;</p>"
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertFalse(plain.unicodeScalars.contains { $0.value >= 0xE000 && $0.value <= 0xF8FF }, plain)
        XCTAssertTrue(plain.contains("sanctificólo"), plain)
    }
}
