import XCTest
@testable import Espada

final class QueryNormalizerTests: XCTestCase {
    func testDictionaryVariantsIncludeAccentedFormForUnaccentedQuery() {
        let variants = QueryNormalizer.dictionaryVariants("arbol")
        XCTAssertTrue(
            variants.contains(where: { $0.caseInsensitiveCompare("árbol") == .orderedSame }),
            "expected accented árbol in \(variants)"
        )
        XCTAssertTrue(
            variants.contains(where: { $0.caseInsensitiveCompare("arbol") == .orderedSame })
        )
    }

    func testDictionaryVariantsStripPunctuationAndFoldCase() {
        let variants = QueryNormalizer.dictionaryVariants("«Árbol»")
        XCTAssertTrue(variants.contains(where: { $0.caseInsensitiveCompare("árbol") == .orderedSame }))
        XCTAssertTrue(variants.contains(where: { $0.caseInsensitiveCompare("arbol") == .orderedSame }))
    }

    func testDictionaryVariantsPluralStemStaysLongEnough() {
        let variants = QueryNormalizer.dictionaryVariants("árboles")
        // stem "arbol" / "árbol" is useful; never emit tiny fragments
        XCTAssertTrue(variants.contains(where: { $0.caseInsensitiveCompare("arbol") == .orderedSame }))
        XCTAssertFalse(variants.contains(where: { $0.count < 3 && !$0.isEmpty }))
    }

    func testSpanishAccentExpansionsBounded() {
        let expanded = QueryNormalizer.spanishAccentExpansions("arbol")
        XCTAssertTrue(expanded.contains("arbol"))
        XCTAssertTrue(expanded.contains("árbol"))
        XCTAssertLessThanOrEqual(expanded.count, 16)
    }

    func testPrimaryProbesStaySmall() {
        let primary = QueryNormalizer.primaryDictionaryProbes("arboles")
        XCTAssertFalse(primary.isEmpty)
        XCTAssertLessThanOrEqual(primary.count, 6)
    }

    func testHeadwordStripsDRAEGloss() {
        XCTAssertEqual(QueryNormalizer.headword(from: "arbolado, da"), "arbolado")
        XCTAssertEqual(QueryNormalizer.headword(from: "casa (sust.)"), "casa")
        XCTAssertEqual(QueryNormalizer.headword(from: "ÁRBOL"), "ÁRBOL")
    }

    /// Precision contract: looking up "arbol" must be able to exact-match "árbol" / "ÁRBOL"
    /// without relying on loose substring search (which also matches enarbolar, etc.).
    func testArbolLookupPrecisionContract() {
        let variants = QueryNormalizer.dictionaryVariants("arbol")
        // Must include exact headword forms used by Spanish modules
        XCTAssertTrue(
            variants.contains(where: { $0.caseInsensitiveCompare("árbol") == .orderedSame }),
            "missing accented lower form in \(variants)"
        )
        // SQLite NOCASE does not fold á↔Á; modules often store ALL CAPS topics.
        XCTAssertTrue(
            variants.contains("ÁRBOL"),
            "missing ÁRBOL for exact SQLite match in \(variants)"
        )
        // Must NOT require mid-string fragments as query forms
        XCTAssertFalse(variants.contains("arb"))
        XCTAssertFalse(variants.contains("ol"))
        XCTAssertFalse(variants.contains("rbol"))
    }

    func testLiveDictionaryExactArbolNotArbusto() throws {
        // Prefer a known Spanish concordance in Downloads if present.
        let candidates = [
            "/Users/amed301/Downloads/E-Sword for Apple (3)/00_NC-STRONG-E_Nueva_Concordancia_Strong_Exhaustiva.dcti",
            "/Users/amed301/Downloads/E-Sword for Apple (3)/nc-strong-e_nueva_concordancia_strong_exhaustiva.dcti",
            "/Users/amed301/Downloads/E-Sword for Apple (3)/nuevo.dcti",
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw XCTSkip("No Spanish dictionary module available for integration check")
        }
        let db = try ModuleDatabase(path: path)
        let results = try db.dictionaryLookup(query: "arbol", limit: 20)
        let topics = results.map(\.topic)
        XCTAssertFalse(topics.isEmpty, "expected at least one hit for arbol in \(path)")
        // Exact headword should win; loose relatives must not appear from substring search.
        let lowered = topics.map { $0.lowercased() }
        XCTAssertFalse(lowered.contains(where: { $0.contains("arbusto") && !$0.hasPrefix("árbol") && !$0.hasPrefix("arbol") }))
        XCTAssertFalse(lowered.contains(where: { $0.hasPrefix("enarbol") || $0.hasPrefix("desarbol") || $0.contains("hiperbol") }))
        // Prefer a true tree headword among results
        XCTAssertTrue(
            lowered.contains(where: { $0 == "árbol" || $0 == "arbol" || QueryNormalizer.headword(from: $0).lowercased() == "árbol" || QueryNormalizer.headword(from: $0).lowercased() == "arbol" }),
            "topics=\(topics)"
        )
    }
}
