import XCTest
@testable import Espada

/// Regression tests for interlinear alignment notation leaking into reading text.
///
/// `rawGenesis11` and `rawJohn316` below are the **verbatim** `Scripture` fields of
/// `00Interlineal-iRV 1960+.bbli` (Book 1 / 43). Before this pass, Génesis 1:1
/// rendered as:
///
/// ```
/// בְּ 1 PB En → el רֵאשִׁית 2 H7225 :NCcSFC principio בָּרָא 3 H1254 :VqAsSM3 creó …
/// ```
final class InterlinearNotationTests: XCTestCase {

    private let rawGenesis11 = #"<heb>בְּ</heb>1 <span style="color:#804DB3;"><sup> PB</sup></span> <blu>En</blu> <heb>→</heb> <span style="color:#C0C0C0;">el</span> <heb>רֵאשִׁית</heb>2 <num>H7225</num>:NCcSFC <blu>principio</blu> <heb>בָּרָא</heb>3 <num>H1254</num>:VqAsSM3 <blu>creó</blu> <heb>אֱלֹהִים</heb>4 <num>H430</num>:NPDSMN <blu>Dios</blu> <heb>אֵת</heb>5 <num>H853</num>:PA <blu>•</blu> <heb>הַ</heb>6 <span style="color:#804DB3;"><sup> XD</sup></span> <blu>los</blu> <heb>שָּׁמַיִם</heb>7 <num>H8064</num>:NCcDMNH <blu>cielos</blu> <heb>וְ</heb>8 <span style="color:#804DB3;"><sup> CC</sup></span> <blu>y</blu> <heb>אֵת</heb>9 <num>H853</num>:PA <blu>•</blu> <heb>הָ</heb>10 <span style="color:#804DB3;"><sup> XD</sup></span> <blu>la</blu> <heb>אָרֶץ</heb>11 <num>H776</num>:NCcSFPH <blu>tierra.</blu>"#

    private let rawJohn316 = #"<grk>γὰρ2</grk> gar <num>G1063</num> C <blu>Porque</blu> <grk>→</grk> <span style="color:#C0C0C0;">de</span> <grk>Οὕτω1</grk> Houtô <num>G3779</num> B <blu>manera</blu> <grk>ἠγάπησεν3</grk> êgapêsen <num>G25</num> VAAI3S <blu>amó</blu> ‹ <grk>ὁ4 Θεὸς5</grk> › ho Theos <num>G3588</num> <num>G2316</num> DNSM NNSM <blu>Dios</blu> <grk>τὸν6</grk> ton <num>G3588</num> DASM <blu>al</blu> <grk>κόσμον7</grk> kosmon <num>G2889</num> NASM <blu>mundo,</blu> <grk>► 10</grk> <blu>a</blu> <grk>αὐτοῦ11</grk> autou <num>G846</num> RP-GSM <blu>su</blu>"#

    // MARK: - Hebrew OT

    func testHebrewInterlinearDropsMorphOrderAndArrowNotation() {
        let plain = ESwordText.moduleFieldToPlain(rawGenesis11)

        // Morphology codes — colon-glued and purple <sup> tags alike
        XCTAssertFalse(plain.contains("NCcSFC"), plain)
        XCTAssertFalse(plain.contains("VqAsSM3"), plain)
        XCTAssertFalse(plain.contains("NPDSMN"), plain)
        XCTAssertFalse(plain.contains("PB"), plain)
        XCTAssertFalse(plain.contains("XD"), plain)
        XCTAssertFalse(plain.contains("CC"), plain)
        // Word-order indices
        XCTAssertFalse(plain.contains("1 "), plain)
        XCTAssertFalse(plain.contains(" 2 "), plain)
        XCTAssertFalse(plain.contains(" 11"), plain)
        // Alignment arrows, orphaned colons, particle bullets
        XCTAssertFalse(plain.contains("→"), plain)
        XCTAssertFalse(plain.contains(":"), plain)
        XCTAssertFalse(plain.contains("•"), plain)
    }

    func testHebrewInterlinearKeepsEverySpanishWordAndHebrew() {
        let plain = ESwordText.moduleFieldToPlain(rawGenesis11)

        for word in ["En", "principio", "creó", "Dios", "los", "cielos", "la", "tierra."] {
            XCTAssertTrue(plain.contains(word), "lost «\(word)» from: \(plain)")
        }
        // Supplied word rendered by the translators — real Spanish, must survive
        XCTAssertTrue(plain.contains("el"), plain)
        // Hebrew lemmas must survive intact
        XCTAssertTrue(plain.contains("רֵאשִׁית"), plain)
        XCTAssertTrue(plain.contains("אֱלֹהִים"), plain)
    }

    // MARK: - Greek NT

    func testGreekInterlinearDropsMorphRunsPointersAndBrackets() {
        let plain = ESwordText.moduleFieldToPlain(rawJohn316)

        for morph in ["VAAI3S", "DNSM", "NNSM", "DASM", "NASM", "RP-GSM"] {
            XCTAssertFalse(plain.contains(morph), "leaked \(morph): \(plain)")
        }
        XCTAssertFalse(plain.contains("►"), plain)
        XCTAssertFalse(plain.contains("‹"), plain)
        XCTAssertFalse(plain.contains("›"), plain)
        XCTAssertFalse(plain.contains("→"), plain)
        // Order indices glued to Greek
        XCTAssertFalse(plain.contains("γὰρ2"), plain)
        XCTAssertFalse(plain.contains("Οὕτω1"), plain)
    }

    func testGreekInterlinearKeepsSpanishGreekAndTransliteration() {
        let plain = ESwordText.moduleFieldToPlain(rawJohn316)

        for word in ["Porque", "manera", "amó", "Dios", "mundo,", "su"] {
            XCTAssertTrue(plain.contains(word), "lost «\(word)» from: \(plain)")
        }
        XCTAssertTrue(plain.contains("ἠγάπησεν"), plain)
        // Transliteration IS the pronunciation — never notation, must survive
        XCTAssertTrue(plain.contains("êgapêsen"), plain)
        XCTAssertTrue(plain.contains("kosmon"), plain)
    }

    // MARK: - Strong markers still resolve

    func testStrongMarkersSurviveNotationStripping() {
        let marked = ESwordText.cleanToMarkers(rawGenesis11)
        for code in ["H7225", "H1254", "H430", "H853", "H8064", "H776"] {
            XCTAssertTrue(marked.contains("⟦STRONG:\(code)⟧"), "lost \(code): \(marked)")
        }
    }

    /// Reverse lookup parses the **raw** field, so notation stripping must not affect it.
    func testInterlinearTokenParsingIsUnaffected() {
        let tokens = StrongResolve.parseInterlinearTokens(rawGenesis11)
        XCTAssertTrue(tokens.contains { $0.spanish == "principio" && $0.strongs == ["H7225"] }, "\(tokens)")
        XCTAssertTrue(tokens.contains { $0.spanish == "creó" && $0.strongs == ["H1254"] }, "\(tokens)")
    }

    /// `00Interlineal-iRV 1960+.bbli` Salmo 23:1 verbatim. Here the untranslated-particle
    /// bullet is **bare** between two glosses, not wrapped in `<blu>`.
    func testBareParticleBulletBetweenGlossesIsDropped() {
        let raw = #"<heb>מִזְמוֹר</heb>1 <num>H4210</num>:NCcSMN <blu>Salmo</blu> <heb>לְ</heb>2 <span style="color:#804DB3;"><sup> PL</sup></span> <blu>de</blu> <heb>דָוִד</heb>3 <num>H1732</num>:NPHSMN <blu>David.</blu> <heb>יהוה</heb>4 <num>H3068</num>:NPDSMN <blu>Jehová</blu> • <blu>es</blu> <heb>ִי</heb>6 <span style="color:#804DB3;"><sup> RBSC1</sup></span> <blu>mi</blu> <heb>רֹע</heb>5 <num>H7462</num>:VqAtSM-S <blu>pastor;</blu>"#

        let plain = ESwordText.moduleFieldToPlain(raw)

        XCTAssertFalse(plain.contains("•"), plain)
        XCTAssertFalse(plain.contains("PL"), plain)
        XCTAssertFalse(plain.contains("RBSC1"), plain)
        XCTAssertFalse(plain.contains("NPDSMN"), plain)
        XCTAssertFalse(plain.contains("VqAtSM-S"), plain)
        for word in ["Salmo", "de", "David.", "Jehová", "es", "mi", "pastor;"] {
            XCTAssertTrue(plain.contains(word), "lost «\(word)» from: \(plain)")
        }
    }

    // MARK: - Modules that must NOT be touched

    /// `01BTX2.dcti` uses `►` as an ordinary bullet. No `<num>`/`<blu>` ⇒ gate is off.
    func testCommentaryBulletsAreNotStripped() {
        let raw = #"<p>No es el lector quien juzga al Libro, sino... 1 &#x25BA; Las Bases Textuales de la Biblia.</p>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("►"), plain)
        XCTAssertTrue(plain.contains("1"), plain)
    }

    /// Strong lexicon lemmas are `#800080` purple — the same family as the interlinear
    /// morph purple. They must survive untouched.
    func testLexiconPurpleLemmaIsNotStripped() {
        let raw = #"<p><span style="color:#800080;">&#x05DC;&#x05B5;&#x05D1;</span></p><p><span style="color:#000080;font-weight:bold;">leb</span></p>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("לֵב"), plain)
        XCTAssertTrue(plain.contains("leb"), plain)
    }

    /// The structural morph rule is shape-checked: an unknown `<blu>` module that puts
    /// real lowercase Spanish between `</num>` and `<blu>` must keep those words.
    func testLowercaseSpanishBetweenNumAndBluIsNotMistakenForMorphology() {
        let raw = #"<grk>λόγος</grk> logos <num>G3056</num> palabra suya <blu>verbo</blu>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("palabra"), plain)
        XCTAssertTrue(plain.contains("suya"), plain)
        XCTAssertTrue(plain.contains("verbo"), plain)
    }

    /// Plain "RV1960 + números Strong" has no `<blu>`; text after `</num>` is Scripture,
    /// not morphology, and must never be eaten by the structural rule.
    func testPlainStrongBibleTextAfterNumIsNotStripped() {
        let raw = #"Deléitate <num>H6026</num> asimismo <num>H5921</num> en Jehová <num>H3068</num>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("Deléitate"), plain)
        XCTAssertTrue(plain.contains("asimismo"), plain)
        XCTAssertTrue(plain.contains("Jehová"), plain)
        XCTAssertTrue(plain.contains("H6026"), plain)
    }
}
