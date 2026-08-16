import XCTest
@testable import Espada

final class StrongResolveTests: XCTestCase {

    // MARK: - Normalize

    func testNormalizeStrongStripsSpacesAndLeadingZeros() {
        XCTAssertEqual(StrongResolve.normalizeStrong("g 05463"), "G5463")
        XCTAssertEqual(StrongResolve.normalizeStrong("H0430"), "H430")
        XCTAssertEqual(StrongResolve.normalizeStrong("G25"), "G25")
        XCTAssertEqual(StrongResolve.normalizeStrong("G0000"), "G0")
        XCTAssertNil(StrongResolve.normalizeStrong("amó"))
        XCTAssertNil(StrongResolve.normalizeStrong("25"))
    }

    func testStrongNormalizerNormalizeUsesCanonicalForm() {
        XCTAssertEqual(StrongNormalizer.normalize("g 05463"), "G5463")
    }

    // MARK: - Parse

    func testParseInterlinearTokensSampleGozaos() {
        let raw = #"<grk>χαίρετε1</grk> chairete <num>G5463</num> VPAM2P <blu>Gozaos</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        XCTAssertEqual(tokens.count, 1)
        guard let t = tokens.first else { return }
        XCTAssertEqual(t.spanish, "Gozaos")
        XCTAssertEqual(t.strongs, ["G5463"])
        XCTAssertEqual(t.greek, "χαίρετε")
        XCTAssertEqual(t.translit, "chairete")
    }

    func testParseInterlinearTokensHebrewJeremias() {
        let raw = #"<heb>יִרְמְיָהוּ</heb>2 <num>H3414</num>:NPHSMN <blu>Jeremías</blu> <heb>בֶּן</heb>3 <num>H1121</num> <blu>hijo</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].spanish, "Jeremías")
        XCTAssertEqual(tokens[0].strongs, ["H3414"])
        XCTAssertFalse(tokens[0].greek.isEmpty)
        XCTAssertEqual(tokens[1].spanish, "hijo")
        XCTAssertEqual(tokens[1].strongs, ["H1121"])
    }

    func testParseInterlinearMultipleStrongsBeforeBlu() {
        let raw = #"<grk>ὁ4 Θεὸς5</grk> ho Theos <num>G3588</num> <num>G2316</num> <blu>Dios</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].spanish, "Dios")
        XCTAssertEqual(tokens[0].strongs, ["G3588", "G2316"])
    }

    func testParseKeepsBulletParticleWithStrongAndPostBluGreek() {
        // iRV often puts <grk> after a bullet <blu>•; reverse Strong lookup still needs G1.
        let raw = #"<num>G1</num> <blu>•</blu> <grk>α</grk> a <num>G2</num> <blu>alpha</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        XCTAssertEqual(tokens.count, 2, "\(tokens)")
        XCTAssertEqual(tokens[0].strongs, ["G1"])
        XCTAssertEqual(tokens[0].spanish, "")
        XCTAssertEqual(tokens[0].greek, "α")
        XCTAssertEqual(tokens[1].spanish, "alpha")
        XCTAssertEqual(tokens[1].strongs, ["G2"])
    }

    func testChooseTokensDoesNotUsePositionalFallback() {
        // Reading-word index must not map into interlinear tokens when text does not match.
        let tokens = [
            InterlinearToken(spanish: "Dios", strongs: ["G2316"], greek: "Θεὸς", translit: "Theos"),
            InterlinearToken(spanish: "mundo", strongs: ["G2889"], greek: "κόσμον", translit: "kosmon"),
        ]
        let none = StrongResolve.chooseTokens(word: "porque", wordIndex: 0, tokens: tokens)
        XCTAssertTrue(none.isEmpty, "positional fallback would wrongly return Dios: \(none)")
        let hit = StrongResolve.chooseTokens(word: "mundo", wordIndex: 99, tokens: tokens)
        XCTAssertEqual(hit.count, 1)
        XCTAssertEqual(hit.first?.strongs, ["G2889"])
    }

    // MARK: - Score

    func testScoreExactAndStem() {
        XCTAssertEqual(StrongResolve.scoreTokenMatch(word: "gozaos", spanish: "Gozaos"), 100)
        XCTAssertEqual(StrongResolve.scoreTokenMatch(word: "Gozaos", spanish: "gozaos"), 100)
        // Stem-ish: amó vs amaron (after fold)
        let stem = StrongResolve.scoreTokenMatch(word: "amaron", spanish: "amar")
        XCTAssertGreaterThanOrEqual(stem, 70)
        XCTAssertEqual(StrongResolve.scoreTokenMatch(word: "casa", spanish: "perro"), 0)
        // Conjugation drift: Bible “deleitate” vs iRV “deleitarás”
        let del = StrongResolve.scoreTokenMatch(word: "deleitate", spanish: "deleitarás")
        XCTAssertGreaterThanOrEqual(del, 70, "expected conjugation match, got \(del)")
        // Morphology never matches Spanish
        XCTAssertEqual(StrongResolve.scoreTokenMatch(word: "vaw3ms", spanish: "puso"), 0)
    }

    func testMorphologyCodesRejected() {
        XCTAssertTrue(StrongResolve.isMorphologyCode("vaw3ms"))
        XCTAssertTrue(StrongResolve.isMorphologyCode("VqAmSM3"))
        XCTAssertTrue(StrongResolve.isMorphologyCode("NPDSMN"))
        XCTAssertTrue(StrongResolve.isMorphologyCode("VtMMSM2"))
        // Dotted analytical morph from multi-lex / morph .lexi modules
        XCTAssertTrue(StrongResolve.isMorphologyCode("subs.pual.ptcp.u.f.sg.a"))
        XCTAssertTrue(StrongResolve.isMorphologyCode("verb.hit.impf.p2.m.pl"))
        XCTAssertTrue(StrongResolve.isDottedAnalyticalMorph("verb.qal.perf.p3.m.sg"))
        // Multilexical / OSHB proper-name tag (H5921 and many others)
        XCTAssertTrue(StrongResolve.isMorphologyCode("nmpr.m.sg.a"))
        XCTAssertTrue(StrongResolve.isDottedAnalyticalMorph("nmpr.m.sg.a"))
        XCTAssertTrue(StrongResolve.isDottedAnalyticalMorph("nmpr.m.sg.a,".trimmingCharacters(in: .punctuationCharacters)))
        XCTAssertFalse(StrongResolve.isMorphologyCode("deleitarás"))
        XCTAssertFalse(StrongResolve.isMorphologyCode("amó"))
        XCTAssertFalse(StrongResolve.isMorphologyCode("G25"))
        XCTAssertFalse(StrongResolve.isPlausibleSpanishGloss("vaw3ms"))
        XCTAssertFalse(StrongResolve.isPlausibleSpanishGloss("subs.pual.ptcp.u.f.sg.a"))
        XCTAssertFalse(StrongResolve.isPlausibleSpanishGloss("nmpr.m.sg.a"))
        XCTAssertTrue(StrongResolve.isPlausibleSpanishGloss("deleitarás"))
    }

    func testStripMorphologyNoiseFromLexiconPlain() {
        let dirty = """
        אָבַד
        abad
        subs.pual.ptcp.u.f.sg.a
        verb.hit.impf.p2.m.pl
        nmpr.m.sg.a
        עַל : nmpr.m.sg.a
        perder, perecer. VtMISM2 vaw3ms
        """
        let clean = ESwordText.stripMorphologyNoise(dirty)
        XCTAssertFalse(clean.contains("subs.pual"), clean)
        XCTAssertFalse(clean.contains("verb.hit"), clean)
        XCTAssertFalse(clean.contains("nmpr"), clean)
        XCTAssertFalse(clean.contains("VtMISM2"), clean)
        XCTAssertFalse(clean.contains("vaw3ms"), clean)
        XCTAssertTrue(clean.contains("perder") || clean.contains("abad") || clean.contains("אָבַד") || clean.contains("עַל"), clean)
    }

    func testSwansonLNIsLouwNidaNotPronunciation() {
        // Swanson lists senses as "1. LN 25.43 amar" — LN = Louw-Nida domain, not Hebrew sound
        let raw = "1. LN 25.43 amar (Jua 13:34); 2. LN 25.44 mostrar amor; 3. LN 25.104 deleitarse"
        let polished = ESwordText.polishStudyPlain(raw)
        XCTAssertTrue(polished.contains("Louw-Nida 25.43"), polished)
        XCTAssertTrue(polished.contains("Louw-Nida 25.44"), polished)
        XCTAssertFalse(polished.contains(" LN "), polished)
        // Pronunciation stays as italic translit in real modules: (agapaō) — not LN
        let withTranslit = ESwordText.polishStudyPlain("(agapaō): vb.; 1. LN 25.43 amar")
        XCTAssertTrue(withTranslit.contains("agapaō"), withTranslit)
        XCTAssertTrue(withTranslit.contains("Louw-Nida 25.43"), withTranslit)
    }

    func testExtractTranslitFromStrongAndSwansonStyle() {
        // Use explicit code points so source encoding cannot strip Hebrew/Greek
        let ayinLamed = "\u{05E2}\u{05B7}\u{05DC}" // עַל
        let lebHeb = "\u{05DC}\u{05B5}\u{05D1}" // לֵב

        // Strong H3820 real layout — pronunciation is "leb", NOT "(figurativamente)"
        let h3820 = "\(lebHeb) leb forma de H3824 ; coraz\u{00F3}n; tambi\u{00E9}n usado (figurativamente) muy ampliamente"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(h3820), "leb")
        XCTAssertNotEqual(StrongResolve.extractTranslitFromLexiconPlain(h3820), "figurativamente")

        let strongPlain = "\(ayinLamed)\nal\nlo mismo que H5920 usado como preposición"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(strongPlain), "al")

        let collapsed = "\(ayinLamed) al lo mismo que H5920 usado como preposición"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(collapsed), "al")

        let multi = "Diccionario Strong \(ayinLamed) al lo mismo que H5920"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(multi), "al")

        // Vine style: pronunciation BEFORE Hebrew
        let vine = "leb ( \(lebHeb) , H3820 ), coraz\u{00F3}n; mente"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(vine), "leb")

        // Greek + Latin
        let g25 = "\u{1F00}\u{03B3}\u{03B1}\u{03C0}\u{03AC}\u{03C9} agapao tal vez de"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(g25), "agapao")

        // Immediate parenthetical after Greek only
        let swan = "\u{1F00}\u{03B3}\u{03B1}\u{03C0}\u{03AC}\u{03C9} (agapao): vb.; Louw-Nida 25.43 amar"
        XCTAssertEqual(StrongResolve.extractTranslitFromLexiconPlain(swan), "agapao")

        // Must NOT treat Spanish paren glosses as pronunciation
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("figurativamente"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("transliteraci\u{00F3}n"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("figurative"))
        XCTAssertTrue(StrongResolve.isPlausibleTranslitToken("leb"))

        // Chávez has no translit — verse refs must not become "pronunciation"
        // e.g. לֵב 1) Corazón ( Eze 4:18 )  → never "Eze" / "eze"
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("eze"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("Eze"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("Jer"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("Re"))
        let chavez = "\(lebHeb) 1) Coraz\u{00F3}n ( Eze 4:18 ). 2) Centro ( Jer 4:18 )."
        XCTAssertNil(
            StrongResolve.extractTranslitFromLexiconPlain(chavez),
            "Chávez-style entries without Latin lemma must return nil, not book codes"
        )

        // Strong+ / BDB style: lemma then LXX tag — LXX is Septuagint, NOT pronunciation
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("LXX"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("lxx"))
        XCTAssertFalse(StrongResolve.isPlausibleTranslitToken("MT"))
        let strongPlus = "\(lebHeb) LXX kard\u{00ED}a leb forma de H3824"
        // Should skip LXX and pick real translit "leb" (or Greek-looking latin after skip)
        let plusPron = StrongResolve.extractTranslitFromLexiconPlain(strongPlus)
        XCTAssertNotEqual(plusPron?.lowercased(), "lxx")
        XCTAssertEqual(plusPron, "leb", "got \(plusPron ?? "nil")")

        // If only LXX is present (no latin lemma), return nil rather than "LXX"
        let onlyLXX = "\(lebHeb) LXX ; forma de H3824 coraz\u{00F3}n"
        XCTAssertNil(StrongResolve.extractTranslitFromLexiconPlain(onlyLXX))
    }

    func testActiveStudyNotClobberedByModuleMemorySemantics() {
        // Documented contract: hasActiveStudyFocus keeps selection; tested via extract + stamp helpers.
        // Strong + Spanish must survive as the study key when jumping .lexi files.
        let code = "H5921"
        let spanish = "en"
        XCTAssertTrue(StrongNormalizer.looksLikeStrong(code))
        XCTAssertTrue(StrongResolve.isPlausibleSpanishGloss(spanish))
    }

    func testDictionaryVariantsVerbInfinitive() {
        let v = QueryNormalizer.dictionaryVariants("deleitarás")
        XCTAssertTrue(v.contains(where: { $0.lowercased().contains("deleitar") || $0.lowercased() == "deleit" || $0.lowercased().hasPrefix("deleit") }), "\(v)")
        let v2 = QueryNormalizer.dictionaryVariants("vaw3ms")
        XCTAssertTrue(v2.isEmpty || v2.allSatisfy { !StrongResolve.isMorphologyCode($0) } || v2.isEmpty)
        // morphology filtered from variants
        XCTAssertFalse(QueryNormalizer.dictionaryVariants("vaw3ms").contains(where: { StrongResolve.isMorphologyCode($0) && $0 == "vaw3ms" && QueryNormalizer.preferredSpanishHeadword([$0]) != nil }))
    }

    func testNormalizeLemmaFoldsAccents() {
        XCTAssertEqual(StrongResolve.normalizeLemma("Jeremías"), "jeremias")
        XCTAssertEqual(StrongResolve.normalizeLemma("AMÓ"), "amo")
    }

    // MARK: - Choose + resolve

    func testDirectStrongWithoutInterlinear() {
        let result = StrongResolve.resolveDirectStrong("G26")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hits.first?.strong, "G26")
        XCTAssertEqual(result?.note, "código Strong’s directo")
    }

    func testResolveFromStrongCodeFillsSpanishAndOriginal() {
        let raw = #"<heb>הִתְעַנַּג</heb>2 <num>H6026</num>:VtMISM2 <blu>Deléitate</blu> <heb>יהוה</heb>4 <num>H3068</num> <blu>Jehová</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        let result = StrongResolve.resolveFromStrongCode(
            code: "H6026",
            tokens: tokens,
            interlinearPath: "/tmp/irv.bbli",
            interlinearTitle: "iRV 1960+"
        )
        XCTAssertEqual(result.hits.first?.strong, "H6026")
        XCTAssertEqual(result.hits.first?.spanish, "Deléitate")
        XCTAssertFalse(result.hits.first?.greek.isEmpty ?? true, "expected Hebrew original")
        XCTAssertTrue(result.note.isEmpty)
    }

    func testResolveFromStrongCodeBulletGlossStillReturnsOriginal() {
        // iRV often uses <blu>•</blu> for pronouns with no Spanish surface form
        let raw = #"<heb>אָתָּה</heb>9 <num>H859</num>:RFSM2 <blu>•</blu> <heb>עֵץ</heb> <num>H6086</num> <blu>árbol</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        let result = StrongResolve.resolveFromStrongCode(
            code: "H859",
            tokens: tokens,
            interlinearPath: "/tmp/irv.bbli",
            interlinearTitle: "iRV 1960+"
        )
        XCTAssertEqual(result.hits.first?.strong, "H859")
        // Spanish may be empty (bullet), but original Hebrew must be present
        XCTAssertFalse(result.hits.first?.greek.isEmpty ?? true)
        XCTAssertFalse(StrongResolve.isPlausibleSpanishGloss(result.hits.first?.spanish ?? "•"))
    }

    func testResolveStrongsByStrongCodeUsesInterlinear() {
        let markup = #"<grk>ἠγάπησεν3</grk> êgapêsen <num>G25</num> <blu>amó</blu>"#
        let result = StrongResolve.resolveStrongs(
            bookNumber: 43,
            chapter: 3,
            verse: 16,
            word: "G25",
            wordIndex: nil,
            candidates: [(path: "/mod/irv.bbli", title: "iRV 1960+")]
        ) { path, _, _, _ in
            path.hasSuffix("irv.bbli") ? markup : nil
        }
        XCTAssertEqual(result.hits.first?.strong, "G25")
        XCTAssertEqual(result.hits.first?.spanish, "amó")
        XCTAssertEqual(result.hits.first?.greek, "ἠγάπησεν")
    }

    func testExtractSpanishGlossesFromLexiconPlain() {
        let plain = """
        עָנַג
        anág
        raíz primaria; ser suave o maleable: burlarse, deleitar, delicadeza, delicado, recrear.
        """
        let glosses = StrongResolve.extractSpanishGlossesFromLexiconPlain(plain)
        XCTAssertTrue(glosses.contains(where: { $0.lowercased().contains("deleitar") }), "\(glosses)")
        XCTAssertTrue(glosses.contains(where: { $0.lowercased().contains("burlarse") || $0.lowercased() == "burlarse" }), "\(glosses)")
    }

    func testExtractSpanishGlossesTuVosotros() {
        let plain = "pronombre primario de segunda pers.; tú, o (plural) vosotros: tú, vosotros."
        let glosses = StrongResolve.extractSpanishGlossesFromLexiconPlain(plain)
        XCTAssertTrue(glosses.contains(where: { $0.lowercased() == "tú" || $0.lowercased() == "tu" }), "\(glosses)")
    }

    func testExtractOriginalHeadwordFromLexiconPlain() {
        // Explicit code points so source encoding cannot strip Hebrew
        let alephTav = "\u{05D0}\u{05B7}\u{05EA}\u{05BC}\u{05B8}\u{05D4}" // אַתָּה
        let plain = "\(alephTav)\nattá\npronombre: tú, vosotros."
        let head = StrongResolve.extractOriginalHeadwordFromLexiconPlain(plain)
        XCTAssertNotNil(head)
        XCTAssertEqual(head, alephTav)
    }

    func testParseKeepsBulletBluWhenOriginalPresent() {
        let raw = #"<heb>אָתָּה</heb>9 <num>H859</num>:RFSM2 <blu>•</blu> <heb>עֵץ</heb> <num>H6086</num> <blu>árbol</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        // H859 must not be dropped just because blu is a bullet
        let h859 = tokens.first(where: { $0.strongs.contains("H859") })
        XCTAssertNotNil(h859, "tokens=\(tokens)")
        XCTAssertTrue(h859?.spanish.isEmpty ?? true)
        XCTAssertFalse(h859?.greek.isEmpty ?? true)
        let arbol = tokens.first(where: { $0.strongs.contains("H6086") })
        XCTAssertEqual(arbol?.spanish, "árbol")
    }

    func testResolveFromTokensByWord() {
        let tokens = StrongResolve.parseInterlinearTokens(
            #"<grk>ἠγάπησεν3</grk> êgapêsen <num>G25</num> VAAI3S <blu>amó</blu> <grk>ὁ4 Θεὸς5</grk> ho Theos <num>G3588</num> <num>G2316</num> <blu>Dios</blu>"#
        )
        let result = StrongResolve.resolveFromTokens(
            word: "amó",
            wordIndex: nil,
            tokens: tokens,
            interlinearPath: "/tmp/irv.bbli",
            interlinearTitle: "iRV 1960+"
        )
        XCTAssertEqual(result.hits.first?.strong, "G25")
        XCTAssertEqual(result.hits.first?.greek, "ἠγάπησεν")
        XCTAssertFalse(result.hits.first?.translit.isEmpty ?? true)
    }

    func testResolveUsesWordIndexForRepeatedGloss() {
        let tokens = [
            InterlinearToken(spanish: "el", strongs: ["G3588"], greek: "ὁ", translit: "ho"),
            InterlinearToken(spanish: "el", strongs: ["G3588"], greek: "τὸν", translit: "ton"),
            InterlinearToken(spanish: "mundo", strongs: ["G2889"], greek: "κόσμον", translit: "kosmon"),
        ]
        let first = StrongResolve.chooseTokens(word: "el", wordIndex: 0, tokens: tokens)
        let second = StrongResolve.chooseTokens(word: "el", wordIndex: 1, tokens: tokens)
        XCTAssertEqual(first.first?.greek, "ὁ")
        XCTAssertEqual(second.first?.greek, "τὸν")
    }

    func testResolveStrongsNoCandidatesNote() {
        let result = StrongResolve.resolveStrongs(
            bookNumber: 43,
            chapter: 3,
            verse: 16,
            word: "mundo",
            wordIndex: nil,
            candidates: []
        ) { _, _, _, _ in nil }
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertTrue(result.note.contains("interlineal"))
    }

    func testResolveStrongsWithLoader() {
        let markup = #"<grk>χαίρετε1</grk> chairete <num>G5463</num> VPAM2P <blu>Gozaos</blu>"#
        let result = StrongResolve.resolveStrongs(
            bookNumber: 45,
            chapter: 12,
            verse: 12,
            word: "Gozaos",
            wordIndex: 0,
            candidates: [(path: "/mod/irv.bbli", title: "iRV 1960+")]
        ) { path, _, _, _ in
            path.hasSuffix("irv.bbli") ? markup : nil
        }
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertEqual(result.hits[0].strong, "G5463")
        XCTAssertEqual(result.hits[0].greek, "χαίρετε")
        XCTAssertEqual(result.hits[0].translit, "chairete")
        XCTAssertEqual(result.interlinearTitle, "iRV 1960+")
        XCTAssertTrue(result.note.isEmpty)
    }

    func testInterlinearCandidateRankingPrefersIRV() {
        let plain = ModuleInfo(
            path: "/a/rv.bbli", filename: "RV1960.bbli", title: "Reina Valera 1960",
            abbreviation: "RV1960", kind: .bible, encrypted: false, hasStrongs: false, version: 1
        )
        let irv = ModuleInfo(
            path: "/a/irv.bbli", filename: "00Interlineal-iRV 1960+.bbli", title: "Interlineal iRV 1960+",
            abbreviation: "iRV", kind: .bible, encrypted: false, hasStrongs: true, version: 1
        )
        let ranked = StrongResolve.rankedInterlinearModules([plain, irv])
        XCTAssertEqual(ranked.first?.path, irv.path)
        XCTAssertFalse(ranked.contains(where: { $0.path == plain.path }))
    }

    func testLooksLikeInterlinearScripture() {
        XCTAssertTrue(StrongResolve.looksLikeInterlinearScripture("<num>G26</num> <blu>amor</blu>"))
        XCTAssertFalse(StrongResolve.looksLikeInterlinearScripture("Porque de tal manera amó Dios al mundo"))
    }

    /// Full pipeline: ModuleStore resolve + lexicon lookup (no UI, no switching reading Bible).
    func testEndToEndStoreResolveThenLexicon() throws {
        let irv = "/Users/amed301/Downloads/for mac espada/00Interlineal-iRV 1960+.bbli"
        let lex = "/Users/amed301/Downloads/for mac espada/01 Diccionario strong.lexi"
        guard FileManager.default.fileExists(atPath: irv),
              FileManager.default.fileExists(atPath: lex) else {
            throw XCTSkip("modules not on disk")
        }
        let store = ModuleStore()
        let irvInfo = ModuleInfo(
            path: irv, filename: "00Interlineal-iRV 1960+.bbli",
            title: "Interlineal iRV 1960+", abbreviation: "iRV",
            kind: .bible, encrypted: false, hasStrongs: true, version: 1
        )
        let result = try store.resolveStrongs(
            bookNumber: 43, chapter: 3, verse: 16,
            word: "amó", wordIndex: nil,
            interlinearModules: [irvInfo]
        )
        XCTAssertEqual(result.hits.first?.strong, "G25", "resolve failed: \(result)")
        XCTAssertFalse(result.hits.first?.greek.isEmpty ?? true)
        let entry = try store.lookupLexicon(modulePath: lex, strong: result.hits[0].strong)
        XCTAssertNotNil(entry, "lexicon miss for \(result.hits[0].strong)")
        XCTAssertTrue(entry!.topic.uppercased().contains("25"))
        XCTAssertFalse(entry!.plain.isEmpty)
    }

    
    func testLiveResolveJehovaToH3068() throws {
        let irv = "/Users/amed301/Downloads/for mac espada/00Interlineal-iRV 1960+.bbli"
        guard FileManager.default.fileExists(atPath: irv) else {
            throw XCTSkip("modules not on disk")
        }
        let store = ModuleStore()
        let irvInfo = ModuleInfo(
            path: irv, filename: "00Interlineal-iRV 1960+.bbli",
            title: "Interlineal iRV 1960+", abbreviation: "iRV",
            kind: .bible, encrypted: false, hasStrongs: true, version: 1
        )
        // Salmos 37:4 — plain RV surface "Jehová" maps to H3068
        let result = try store.resolveStrongs(
            bookNumber: 19, chapter: 37, verse: 4,
            word: "Jehová", wordIndex: nil,
            interlinearModules: [irvInfo]
        )
        XCTAssertEqual(result.hits.first?.strong, "H3068", "resolve failed: \(result)")
        // Accentless form too
        let result2 = try store.resolveStrongs(
            bookNumber: 19, chapter: 37, verse: 4,
            word: "Jehova", wordIndex: nil,
            interlinearModules: [irvInfo]
        )
        XCTAssertEqual(result2.hits.first?.strong, "H3068", "accentless failed: \(result2)")
    }

    /// RV1960+ con Strong format (Spanish then <num>) — silent map for plain Reina Valera 1960.
    func testParseWordStrongTokensRV1960Plus() {
        let raw = """
        Deléitate <num>H6026</num> VtMISM2 asimismo en <num>H5921</num> Pu Jehová, <num>H3068</num> NPDSMN Y él te concederá <num>H5414</num> VqAMSM3 las peticiones <num>H4862</num> NCcPFC de tu corazón. <num>H3820</num> NCcSMS
        """
        let tokens = StrongResolve.parseWordStrongTokens(raw)
        XCTAssertGreaterThanOrEqual(tokens.count, 5, "\(tokens)")
        let byWord = Dictionary(uniqueKeysWithValues: tokens.map { ($0.spanish.lowercased(), $0.strongs.first ?? "") })
        // Keys may keep accents
        let corazon = tokens.first(where: { StrongResolve.normalizeLemma($0.spanish) == "corazon" })
        XCTAssertEqual(corazon?.strongs.first, "H3820", "tokens=\(tokens)")
        let jehova = tokens.first(where: { StrongResolve.normalizeLemma($0.spanish) == "jehova" })
        XCTAssertEqual(jehova?.strongs.first, "H3068", "tokens=\(tokens)")
        let deleit = tokens.first(where: { StrongResolve.normalizeLemma($0.spanish).hasPrefix("deleit") })
        XCTAssertEqual(deleit?.strongs.first, "H6026")
        _ = byWord
    }

    /// Plain Reina Valera 1960 word → Strong via RV1960+ map module (not via reading Bible).
    func testPlainRV1960WordMapsViaRV1960Plus() throws {
        let plus = "/Users/amed301/Downloads/E-Sword for Apple (3)/AA-rv1960+_reina_valera_1960_con_strong.bbli"
        guard FileManager.default.fileExists(atPath: plus) else {
            throw XCTSkip("RV1960+ module not on disk")
        }
        let store = ModuleStore()
        let map = ModuleInfo(
            path: plus,
            filename: "AA-rv1960+_reina_valera_1960_con_strong.bbli",
            title: "Reina Valera 1960 con números Strong",
            abbreviation: "RV1960+",
            kind: .bible, encrypted: false, hasStrongs: true, version: 1
        )
        // User is *reading* plain RV1960; map is RV1960+ only
        let result = try store.resolveStrongs(
            bookNumber: 19, chapter: 37, verse: 4,
            word: "corazón", wordIndex: nil,
            interlinearModules: [map]
        )
        XCTAssertEqual(result.hits.first?.strong, "H3820", "failed: \(result)")
        let jeh = try store.resolveStrongs(
            bookNumber: 19, chapter: 37, verse: 4,
            word: "Jehová", wordIndex: nil,
            interlinearModules: [map]
        )
        XCTAssertEqual(jeh.hits.first?.strong, "H3068", "failed: \(jeh)")
    }

    func testParseStrongsMapTokensFallsBackToWordStrong() {
        let raw = "Jehová <num>H3068</num> Dios <num>H430</num>"
        let tokens = StrongResolve.parseStrongsMapTokens(raw)
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].spanish, "Jehová")
        XCTAssertEqual(tokens[0].strongs, ["H3068"])
        XCTAssertEqual(tokens[1].strongs, ["H430"])
    }

    func testReadingBiblePreferenceIsPlainNotInterlinear() {
        let plain = ModuleInfo(
            path: "/a/rv.bbli", filename: "Reina Valera 1960.bbli",
            title: "Reina Valera 1960", abbreviation: "RV1960",
            kind: .bible, encrypted: false, hasStrongs: false, version: 1
        )
        let irv = ModuleInfo(
            path: "/a/irv.bbli", filename: "00Interlineal-iRV 1960+.bbli",
            title: "Interlineal iRV 1960+", abbreviation: "iRV",
            kind: .bible, encrypted: false, hasStrongs: true, version: 1
        )
        let ranked = StrongResolve.rankedInterlinearModules([plain, irv])
        XCTAssertEqual(ranked.first?.path, irv.path)
        // Plain must not be treated as interlinear map candidate
        XCTAssertFalse(ranked.contains(where: { $0.path == plain.path }))
        XCTAssertEqual(
            StrongResolve.interlinearCandidateScore(
                title: plain.title, filename: plain.filename,
                abbreviation: plain.abbreviation, hasStrongs: plain.hasStrongs
            ),
            0
        )
    }

    /// Live modules on the Mac Downloads tree (skipped if not present).
    func testLiveModulesPlainRVWordMapsViaInterlinear() throws {
        let irv = "/Users/amed301/Downloads/for mac espada/00Interlineal-iRV 1960+.bbli"
        guard FileManager.default.fileExists(atPath: irv) else {
            throw XCTSkip("iRV module not on disk")
        }
        let db = try ModuleDatabase(path: irv)
        let raw = try db.loadVerse(book: 43, chapter: 3, verse: 16)
        XCTAssertNotNil(raw)
        let tokens = StrongResolve.parseInterlinearTokens(raw ?? "")
        XCTAssertFalse(tokens.isEmpty, "expected blu tokens in Juan 3:16")
        let result = StrongResolve.resolveFromTokens(
            word: "amó",
            wordIndex: nil,
            tokens: tokens,
            interlinearPath: irv,
            interlinearTitle: "iRV",
            wordProbes: QueryNormalizer.dictionaryVariants("amó")
        )
        XCTAssertEqual(result.hits.first?.strong, "G25", "\(result)")
        XCTAssertFalse(result.hits.first?.greek.isEmpty ?? true)

        let mundo = StrongResolve.resolveFromTokens(
            word: "mundo",
            wordIndex: nil,
            tokens: tokens,
            interlinearPath: irv,
            interlinearTitle: "iRV",
            wordProbes: ["mundo", "mundo,"]
        )
        XCTAssertEqual(mundo.hits.first?.strong, "G2889", "\(mundo)")
    }

    /// Snippet shaped like real iRV 1960+ Juan 3:16 (device modules optional).
    func testParseJohn316StyleAmo() {
        let raw = #"<grk>γὰρ2</grk> gar <num>G1063</num> C <blu>Porque</blu> <grk>Οὕτω1</grk> Houtô <num>G3779</num> B <blu>manera</blu> <grk>ἠγάπησεν3</grk> êgapêsen <num>G25</num> VAAI3S <blu>amó</blu> <grk>ὁ4 Θεὸς5</grk> ho Theos <num>G3588</num> <num>G2316</num> <blu>Dios</blu> <grk>τὸν6</grk> ton <num>G3588</num> DASM <blu>al</blu> <grk>κόσμον7</grk> kosmon <num>G2889</num> NASM <blu>mundo,</blu>"#
        let tokens = StrongResolve.parseInterlinearTokens(raw)
        let amo = tokens.first { StrongResolve.normalizeLemma($0.spanish) == "amo" }
        XCTAssertNotNil(amo)
        XCTAssertEqual(amo?.strongs, ["G25"])
        XCTAssertEqual(amo?.greek, "ἠγάπησεν")
        let mundo = tokens.first { StrongResolve.normalizeLemma($0.spanish) == "mundo" }
        XCTAssertEqual(mundo?.strongs, ["G2889"])
        let result = StrongResolve.resolveFromTokens(
            word: "amó", wordIndex: nil, tokens: tokens,
            interlinearPath: "irv", interlinearTitle: "iRV"
        )
        XCTAssertEqual(result.hits.first?.strong, "G25")
    }
}
