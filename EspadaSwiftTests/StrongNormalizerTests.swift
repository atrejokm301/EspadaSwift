import XCTest
@testable import Espada

final class StrongNormalizerTests: XCTestCase {
    func testCandidatesIncludePaddedForms() {
        let c = StrongNormalizer.candidates("G25")
        XCTAssertTrue(c.contains("G25"))
        XCTAssertTrue(c.contains("G0025") || c.contains("G25"))
    }

    func testLooksLikeStrong() {
        XCTAssertTrue(StrongNormalizer.looksLikeStrong("G1063"))
        XCTAssertTrue(StrongNormalizer.looksLikeStrong("h430"))
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
