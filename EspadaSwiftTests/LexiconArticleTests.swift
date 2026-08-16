import XCTest
@testable import Espada

/// Structured-article tests built from **real** module markup on disk
/// (`~/Downloads/for mac espada`). Every `raw` below is a faithful excerpt of the
/// stored `Definition` / `Scripture` field, not an invented sample.
final class LexiconArticleTests: XCTestCase {

    // MARK: - Pronunciation (the field the old heuristics kept getting wrong)

    /// `01 Diccionario strong.lexi`, Topic `H3820`.
    /// Navy `#000080` is the pronunciation; the old plain-text scraper had to keep a
    /// hand-written list of Spanish words it must never return instead.
    func testStrongHebrewArticleYieldsLemmaPronunciationAndGlosses() {
        let raw = #"<p><span style="color:#800080;">&#x05DC;&#x05B5;&#x05D1;</span></p><p><span style="color:#000080;font-weight:bold;">leb</span></p><p>forma de <span style="color:#808000;text-decoration:underline ;">H3824</span>; <span style="font-style:italic;">coraz&oacute;n;</span> tambi&eacute;n usado (figurativamente) muy ampliamente para los sentimientos, la voluntad e incluso el intelecto: <span style="color:#CC3333;">amorosamente, angustiar, &aacute;nimo, coraz&oacute;n, cordura, entendimiento.</span></p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.pronunciation, "leb")
        XCTAssertEqual(article.lemma, "לֵב")
        XCTAssertTrue(article.glosses.contains("corazón"), "\(article.glosses)")
        XCTAssertTrue(article.glosses.contains("ánimo"), "\(article.glosses)")
        XCTAssertTrue(article.strongRefs.contains("H3824"), "\(article.strongRefs)")
        // The italic prose gloss must never be mistaken for a pronunciation.
        XCTAssertNotEqual(article.pronunciation, "corazón")
        XCTAssertFalse(article.isEmpty)
    }

    /// `01 Diccionario strong.lexi`, Topic `G26`.
    func testStrongGreekArticleYieldsAccentedPronunciation() {
        let raw = #"<p><span style="color:#800000;font-weight:bold;">&#x1F00;&gamma;&#x03AC;&pi;&eta;</span></p><p><span style="color:#000080;font-weight:bold;">ag&aacute;pe</span></p><p>de <span style="color:#808000;text-decoration:underline ;">G25</span>; <span style="font-style:italic;">amor,</span> i.e. <span style="font-style:italic;">afecto</span> o <span style="font-style:italic;">benevolencia;</span> espec&iacute;ficamente (plural) <span style="font-style:italic;">fest&iacute;n de amor:</span> <span style="color:#CC3333;">&aacute;gape, amado, amor.</span></p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.pronunciation, "agápe")
        XCTAssertEqual(article.lemma, "ἀγάπη")
        XCTAssertTrue(article.glosses.contains("amor"), "\(article.glosses)")
        XCTAssertTrue(article.strongRefs.contains("G25"), "\(article.strongRefs)")
    }

    /// `01 Diccionario Expositivo con numeros Strong Vine.dcti`, Topic `G4`.
    /// Vine prints the pronunciation **before** the Greek — position must not matter.
    func testVinePronunciationBeforeLemma() {
        let raw = #"<p><span style="color:#000080;font-weight:bold;font-style:italic;">abares</span> (<span style="color:#800000;font-weight:bold;">&#x1F00;&beta;&alpha;&rho;&#x03AE;&sigmaf;</span>, <span style="color:#808000;font-style:italic;text-decoration:underline ;">G4</span>), sin peso <span style="font-style:italic;">(a,</span> privativo, y <span style="font-style:italic;">baros,</span> v&eacute;ase CARGAR. Se utiliza en <ref>2Co 11:9</ref>.</p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.pronunciation, "abares")
        XCTAssertEqual(article.lemma, "ἀβαρής")
        XCTAssertTrue(article.strongRefs.contains("G4"), "\(article.strongRefs)")
    }

    /// `01 Diccionario de griego biblico Swanson.lexi`, Topic `G26`.
    /// Swanson marks no navy span — the pronunciation is the italic parenthetical
    /// immediately following the lemma.
    func testSwansonPronunciationFromAdjacentItalicParenthetical() {
        let raw = #"<p><span style="font-weight:bold;">Swanson 27</span></p><p><span style="color:#0099CC;">&#x1F00;&gamma;&#x03AC;&pi;&#x0113;</span> <span style="font-style:italic;">(agap&#x0113;),</span> <span style="color:#0099CC;">&#x0113;&sigmaf;</span> <span style="font-style:italic;">(&#x0113;s),</span> s.fem.; <span style="font-weight:bold;">Strong</span> 26</p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.pronunciation, "agapē")
        XCTAssertEqual(article.lemma, "ἀγάπē")
    }

    /// `01 Diccionario de hebreo biblico Chavez.lexi`, Topic `H3820`.
    /// Chávez marks **no** pronunciation. Returning "" is correct — the old scraper
    /// was liable to hand back the first Spanish word ("Corazón") instead.
    func testChavezArticleReportsNoPronunciationRatherThanASpanishWord() {
        let raw = #"<p><span style="color:#0099CC;">&#x05DC;&#x05B5;&#x05D1;</span></p><p>1) Coraz&oacute;n (<ref>2Re 8:24</ref>).</p><p>2) Centro de la vitalidad (<ref>Jer 4:18</ref>).</p><p>3) Mente, centro de las motivaciones (<span style="color:#008000;text-decoration:underline ;">G&eacute;n_6:5</span>).</p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.lemma, "לֵב")
        XCTAssertEqual(article.pronunciation, "", "must not invent a pronunciation from prose")
    }

    /// `01 Palabras griegas del Nuevo Testamento de Barclay.lexi`, Topic `G26`.
    /// Barclay uses the lemma colour for a **Latin** headword. Colour alone would
    /// wrongly report `AGAPE` as the original-script lemma.
    func testBarclayLatinHeadwordIsNotTreatedAsOriginalScript() {
        let raw = #"<p><span style="color:#0099CC;font-weight:bold;">AGAPE</span><span style="color:#0099CC;font-weight:bold;"><sup>26</sup></span><span style="color:#0099CC;font-weight:bold;"> Y AGAPAN</span></p><p><span style="font-weight:bold;">LA M&Aacute;S GRANDE DE LAS VIRTUDES</span></p><p>La lengua griega es una de las m&aacute;s ricas.</p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.lemma, "", "AGAPE is Latin script, not a Greek lemma")
    }

    // MARK: - Compiled modules

    /// `01 Multilexico de idiomas biblicos en espanol.lexi` bundles six dictionaries
    /// into a single ~52 KB entry, separated by centered bold teal headings.
    func testCompiledModuleSplitsIntoPublisherSections() {
        let raw = #"<p style="text-align:center;"><span style="color:#008080;font-weight:bold;">Diccionario Strong</span></p><p><span style="color:#000080;font-weight:bold;">ag&aacute;pe</span></p><p>amor, afecto.</p><p style="text-align:center;"><span style="color:#008080;font-weight:bold;">L&eacute;xico Griego-Espa&ntilde;ol Tuggy</span></p><p>Amor. El sustantivo del cual agapao es el verbo.</p>"#

        let article = LexiconArticle.parse(raw)

        XCTAssertEqual(article.sections.count, 2, "\(article.sections)")
        XCTAssertEqual(article.sections.first?.title, "Diccionario Strong")
        XCTAssertEqual(article.sections.last?.title, "Léxico Griego-Español Tuggy")
        XCTAssertTrue(article.sections.first?.plain.contains("amor") ?? false)
        XCTAssertTrue(article.sections.last?.plain.contains("sustantivo") ?? false)
        // A section split must not cost the top-level fields.
        XCTAssertEqual(article.pronunciation, "agápe")
    }

    /// A single centered heading is a title, not a compilation.
    func testSingleCenteredHeadingDoesNotProduceSections() {
        let raw = #"<p style="text-align:center;"><span style="font-weight:bold;">Diccionario Strong</span></p><p>amor, afecto.</p>"#
        XCTAssertTrue(LexiconArticle.parse(raw).sections.isEmpty)
    }

    // MARK: - Boundary / invalid input

    func testEmptyAndTaglessInputAreEmptyNotCrashing() {
        XCTAssertTrue(LexiconArticle.parse("").isEmpty)
        XCTAssertTrue(LexiconArticle.parse("texto plano sin ninguna etiqueta").isEmpty)
        XCTAssertTrue(LexiconArticle.parse("<p>").isEmpty)
        XCTAssertTrue(LexiconArticle.parse("<span style=\"color:#000080;\"></span>").isEmpty)
    }

    /// Morphology tags share the pronunciation slot's shape but must never be accepted.
    func testMorphologyCodeIsNeverReturnedAsPronunciation() {
        let raw = #"<p><span style="color:#0099CC;">&#x05DC;&#x05B5;&#x05D1;</span> <span style="font-style:italic;">verb.hit.impf.p2.m.pl</span></p>"#
        XCTAssertEqual(LexiconArticle.parse(raw).pronunciation, "")
    }

    /// An unmarked module yields nothing, so callers keep their plain-text fallback.
    func testUnmarkedArticleIsEmptySoCallersFallBack() {
        let raw = #"<p>Coraz&oacute;n, mente, voluntad. V&eacute;ase tambi&eacute;n <ref>Jer 4:18</ref>.</p>"#
        let article = LexiconArticle.parse(raw)
        XCTAssertTrue(article.isEmpty, "\(article)")
    }
}
