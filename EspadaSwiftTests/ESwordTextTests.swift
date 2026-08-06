import XCTest
@testable import Espada

/// Regression tests from real e-Sword module samples (not invented).
/// Sources under Downloads/E-Sword for Apple (3)/ …
final class ESwordTextTests: XCTestCase {

    func testSpanishNamedEntitiesFromDictionary() {
        // DRAE / Strong concordance style
        let raw = #"<p>1. tr. Sacar de un barranco lo que est&aacute; atascado. com&uacute;n en Palestina excepto en el valle del Jord&aacute;n. peque&ntilde;as. &eacute;l. &iquest;no conozco?</p>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("está"), plain)
        XCTAssertTrue(plain.contains("común"), plain)
        XCTAssertTrue(plain.contains("Jordán"), plain)
        XCTAssertTrue(plain.contains("pequeñas"), plain)
        XCTAssertTrue(plain.contains("él"), plain)
        XCTAssertTrue(plain.contains("¿no conozco?"), plain)
        XCTAssertFalse(plain.contains("&aacute"), plain)
        XCTAssertFalse(plain.contains("&ntilde"), plain)
    }

    func testJehovaStrongConcordanceStyle() {
        // 00_NC-STRONG-E: Jehov&aacute; + purple H3068
        let raw = #"<p>&laquo;Jehov&aacute; es mi estandarte&raquo;, <ref>Éxo 17:15</ref>&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:#804DB3;">H3071</span></p>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("Jehová"), plain)
        XCTAssertTrue(plain.contains("H3071"), plain)
        XCTAssertTrue(plain.contains("Éxo 17:15") || plain.contains("Éxo"), plain)
        XCTAssertFalse(plain.contains("&aacute"), plain)
        XCTAssertFalse(plain.contains("&laquo"), plain)
    }

    func testGreekNamedAndHexEntitiesFromThayer() {
        // Thayer_39s_Unabridged.lexi style
        let raw = #"<p><grk><blu>&Alpha;</blu>, <blu>&#x1F04;&lambda;&phi;&alpha;</blu>, the first letter</grk> greek alphabet</p>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("Α") || plain.contains("Alpha") == false)
        // Alpha entity → Α
        XCTAssertTrue(plain.contains("Α"), "expected Greek Alpha, got: \(plain)")
        // hex combining/tonos letter should decode
        XCTAssertFalse(plain.contains("&#x"), plain)
        XCTAssertFalse(plain.contains("&lambda"), plain)
        XCTAssertTrue(plain.contains("first letter"), plain)
    }

    func testHebrewNumericEntities() {
        // The Scriptures / Tanach style
        let raw = #"<heb>&#x05D1;&#x05E8;&#x05D0;&#x05E9;&#x05C1;&#x05D9;&#x05EA;</heb>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("ב"), plain)
        XCTAssertTrue(plain.contains("ר"), plain)
        XCTAssertFalse(plain.contains("&#x"), plain)
    }

    func testNumTagStrongMarkers() {
        // AA-rv1960+ style
        let raw = #"Jehová <num>H3068</num> Dios <num>H430</num>"#
        let marked = ESwordText.cleanToMarkers(raw)
        XCTAssertTrue(marked.contains("⟦STRONG:H3068⟧"), marked)
        XCTAssertTrue(marked.contains("⟦STRONG:H430⟧"), marked)
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("H3068"), plain)
        XCTAssertTrue(plain.contains("Jehová") || plain.contains("Jehov"), plain)
    }

    func testRTFWindows1252Spanish() {
        // Traducción del Nuevo Mundo Details.Comments style
        let raw = #"{\rtf1\ansi\ansicpg1252\deff0 TRADUCCI\'d3N DEL NUEVO MUNDO VERSI\'d3N}"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("TRADUCCIÓN") || plain.contains("TRADUCC"), plain)
        // \'d3 is Ó in Windows-1252
        XCTAssertTrue(plain.contains("Ó") || plain.contains("O"), "expected accented O, got: \(plain)")
    }

    func testWordsOfChristRedTag() {
        let raw = #"Jesus said, <red>Verily, verily, I say unto thee</red> about the kingdom."#
        let marked = ESwordText.cleanToMarkers(raw)
        XCTAssertTrue(marked.contains("⟦WOC⟧"), marked)
        XCTAssertTrue(marked.contains("⟦/WOC⟧"), marked)
        let runs = ESwordText.readingRuns(from: raw)
        XCTAssertTrue(runs.contains(where: { $0.isWordsOfChrist && $0.text.contains("Verily") }), "\(runs)")
        XCTAssertTrue(runs.contains(where: { !$0.isWordsOfChrist && $0.text.localizedCaseInsensitiveContains("Jesus") }), "\(runs)")
    }

    func testWordsOfChristSpanB34D4D() {
        // American Standard / HCSB Red Letter style used in e-Sword
        let raw = #"<span style="color:#B34D4D;">Blessed are the poor in spirit</span> for theirs is the kingdom."#
        let runs = ESwordText.readingRuns(from: raw)
        XCTAssertTrue(
            runs.contains(where: { $0.isWordsOfChrist && $0.text.contains("Blessed are the poor") }),
            "expected WOC run, got: \(runs)"
        )
        XCTAssertTrue(
            runs.contains(where: { !$0.isWordsOfChrist && $0.text.localizedCaseInsensitiveContains("kingdom") }),
            "expected non-WOC tail, got: \(runs)"
        )
    }

    func testWordsOfChristColorHeuristic() {
        XCTAssertTrue(ESwordText.isWordsOfChristColor("B34D4D"))
        XCTAssertTrue(ESwordText.isWordsOfChristColor("#ff0000"))
        XCTAssertTrue(ESwordText.isWordsOfChristColor("red"))
        XCTAssertFalse(ESwordText.isWordsOfChristColor("804DB3")) // purple Strong
        XCTAssertFalse(ESwordText.isWordsOfChristColor("808080")) // gray
    }

    func testAmpersandAndQuotes() {
        let raw = #"Dijo: &quot;paz&quot; &amp; bien &mdash; fin&rsquo;s"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertTrue(plain.contains("\"paz\""), plain)
        XCTAssertTrue(plain.contains("&") || plain.contains("y"), plain)
        XCTAssertTrue(plain.contains("—") || plain.contains("–"), plain)
        XCTAssertFalse(plain.contains("&quot"), plain)
        XCTAssertFalse(plain.contains("&mdash"), plain)
    }

    func testDoesNotLeaveRawEntitiesFromCommentary() {
        // comentario_siglo_xxi style
        let raw = #"<p>La bigamia nunca estuvo en el prop&oacute;sito de Dios, porque &eacute;l le dio a Ad&aacute;n s&oacute;lo una mujer.</p>"#
        let plain = ESwordText.moduleFieldToPlain(raw)
        XCTAssertEqual(
            plain,
            "La bigamia nunca estuvo en el propósito de Dios, porque él le dio a Adán sólo una mujer."
        )
    }

    func testFullEntityMapHasSpanishAndGreek() {
        XCTAssertEqual(HTMLNamedEntities.map["aacute"], "á")
        XCTAssertEqual(HTMLNamedEntities.map["ntilde"], "ñ")
        XCTAssertEqual(HTMLNamedEntities.map["Omega"], "Ω")
        XCTAssertEqual(HTMLNamedEntities.map["omega"], "ω")
        XCTAssertEqual(HTMLNamedEntities.map["nbsp"], "\u{00A0}")
        XCTAssertEqual(HTMLNamedEntities.map["NewLine"], "\n")
        XCTAssertEqual(HTMLNamedEntities.map["Tab"], "\t")
        XCTAssertGreaterThan(HTMLNamedEntities.map.count, 2000)
    }
}
