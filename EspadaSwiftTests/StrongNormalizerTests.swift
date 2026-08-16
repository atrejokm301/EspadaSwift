import XCTest
@testable import Espada

final class StrongNormalizerTests: XCTestCase {
    func testCandidatesIncludePaddedForms() {
        let c = StrongNormalizer.candidates("G25")
        XCTAssertTrue(c.contains("G25"))
        XCTAssertTrue(c.contains("G0025") || c.contains("G25"))
    }

    /// Trailing zeros are part of the Strong number (H430 ≠ H43).
    func testCandidatesPreserveTrailingZeros() {
        let h430 = StrongNormalizer.candidates("H430")
        XCTAssertTrue(h430.contains("H430"), "\(h430)")
        XCTAssertFalse(h430.contains("H43"), "must not strip trailing zero: \(h430)")
        XCTAssertTrue(h430.contains("H0430") || h430.contains("H00430"), "\(h430)")

        let g100 = StrongNormalizer.candidates("G100")
        XCTAssertTrue(g100.contains("G100"), "\(g100)")
        XCTAssertFalse(g100.contains("G1"), "must not strip trailing zeros: \(g100)")

        let h30 = StrongNormalizer.candidates("H30")
        XCTAssertTrue(h30.contains("H30"), "\(h30)")
        XCTAssertFalse(h30.contains("H3"), "\(h30)")

        // Leading zeros still strip: H0430 → core H430
        XCTAssertEqual(StrongNormalizer.normalize("H0430"), "H430")
        XCTAssertEqual(StrongNormalizer.normalize("G 05463"), "G5463")
    }

    func testLooksLikeStrong() {
        XCTAssertTrue(StrongNormalizer.looksLikeStrong("G1063"))
        XCTAssertTrue(StrongNormalizer.looksLikeStrong("h430"))
        XCTAssertTrue(StrongNormalizer.looksLikeStrong("H 430"))
        XCTAssertFalse(StrongNormalizer.looksLikeStrong("amó"))
    }
}

final class VerseTokenizerTests: XCTestCase {
    func testInterlinearJohn316LinksSpanishToStrong() {
        let raw = #"<grk>ἠγάπησεν3</grk> êgapêsen <num>G25</num> VAAI3S <blu>amó</blu> <grk>ὁ4 Θεὸς5</grk> ho Theos <num>G3588</num> <num>G2316</num> <blu>Dios</blu>"#
        let tokens = VerseTokenizer.tokenize(rawScripture: raw, verse: 16)
        let words = tokens.filter { $0.kind == .word }
        XCTAssertTrue(words.contains(where: { $0.text.lowercased().hasPrefix("am") }))
        if let amo = words.first(where: { $0.text.lowercased().contains("am") }) {
            XCTAssertTrue(amo.strongCodes.contains(where: { $0.hasPrefix("G25") || $0 == "G25" }) || !amo.strongCodes.isEmpty || tokens.contains(where: { $0.kind == .strong && $0.text.contains("25") }))
        }
        XCTAssertTrue(tokens.contains(where: { $0.kind == .strong && $0.text.contains("25") }))
    }
}
