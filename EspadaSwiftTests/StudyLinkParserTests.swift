import XCTest
@testable import Espada

final class StudyLinkParserTests: XCTestCase {

    func testParsesSpanishJehovaConcordanceStyle() {
        let plain = "«Jehová es mi estandarte», Éxo 17:15 H3071"
        let links = StudyLinkParser.findLinks(in: plain)
        XCTAssertTrue(links.contains(where: {
            if case .strong("H3071") = $0 { return true }
            return false
        }), "\(links)")
        XCTAssertTrue(links.contains(where: {
            if case .verse(let b, let c, let v, _) = $0 {
                return b == 2 && c == 17 && v == 15
            }
            return false
        }), "\(links)")
    }

    func testParsesEnglishPhpAndHebrewStrong() {
        let plain = "Lightfoot in Php 2:26; see also H3068 and G26."
        let links = StudyLinkParser.findLinks(in: plain)
        XCTAssertTrue(links.contains(where: {
            if case .verse(let b, let c, let v, _) = $0 {
                return b == 50 && c == 2 && v == 26
            }
            return false
        }), "\(links)")
        XCTAssertTrue(links.contains(where: {
            if case .strong("H3068") = $0 { return true }
            return false
        }))
        XCTAssertTrue(links.contains(where: {
            if case .strong("G26") = $0 { return true }
            return false
        }))
    }

    func testParses1JuanRange() {
        let plain = "See 1 Juan 3:16-18 for context."
        let links = StudyLinkParser.findLinks(in: plain)
        XCTAssertTrue(links.contains(where: {
            if case .verse(let b, let c, let v, let end) = $0 {
                return b == 62 && c == 3 && v == 16 && end == 18
            }
            return false
        }), "\(links)")
    }

    /// e-Sword English commentaries often use Luk / Act / 1Pe / Gen. without Spanish names.
    func testParsesEnglishESwordCommentaryForms() {
        let plain = "See Luk 5:27-29; Act 12:12; 1Pe 5:13; Gen. 38:11-30; Mat 1:16; Joh 1:1; Col 4:10."
        let links = StudyLinkParser.findLinks(in: plain)
        func hasVerse(_ book: Int, _ ch: Int, _ v: Int, end: Int? = nil) -> Bool {
            links.contains {
                if case .verse(let b, let c, let vv, let e) = $0 {
                    return b == book && c == ch && vv == v && (end == nil || e == end)
                }
                return false
            }
        }
        XCTAssertTrue(hasVerse(42, 5, 27, end: 29), "Luk: \(links)")
        XCTAssertTrue(hasVerse(44, 12, 12), "Act: \(links)")
        XCTAssertTrue(hasVerse(60, 5, 13), "1Pe: \(links)")
        XCTAssertTrue(hasVerse(1, 38, 11, end: 30), "Gen.: \(links)")
        XCTAssertTrue(hasVerse(40, 1, 16), "Mat: \(links)")
        XCTAssertTrue(hasVerse(43, 1, 1), "Joh: \(links)")
        XCTAssertTrue(hasVerse(51, 4, 10), "Col: \(links)")
    }

    func testParsesUnderscoreForm() {
        let plain = "Compare Gén_25:16 with the interlinear."
        let links = StudyLinkParser.findLinks(in: plain)
        XCTAssertTrue(links.contains(where: {
            if case .verse(let b, let c, let v, _) = $0 {
                return b == 1 && c == 25 && v == 16
            }
            return false
        }), "\(links)")
    }

    func testResolveBookAliasesFromMacTable() {
        XCTAssertEqual(BibleBooks.resolveBook("Gén"), 1)
        XCTAssertEqual(BibleBooks.resolveBook("Éxo"), 2)
        XCTAssertEqual(BibleBooks.resolveBook("Php"), 50)
        XCTAssertEqual(BibleBooks.resolveBook("Jn"), 43)
        XCTAssertEqual(BibleBooks.resolveBook("Rev"), 66)
        XCTAssertEqual(BibleBooks.resolveBook("1Co"), 46)
        XCTAssertEqual(BibleBooks.resolveBook("Luk"), 42)
        XCTAssertEqual(BibleBooks.resolveBook("Act"), 44)
        XCTAssertEqual(BibleBooks.resolveBook("1Pe"), 60)
        XCTAssertEqual(BibleBooks.resolveBook("Gen."), 1)
        XCTAssertEqual(BibleBooks.resolveBook("Mat"), 40)
        XCTAssertEqual(BibleBooks.resolveBook("Joh"), 43)
    }

    func testStudyLinkURLRoundTrip() {
        let s = StudyLink.strong("H3068")
        let url = s.toURL()!
        XCTAssertEqual(StudyLink.from(url: url), .strong("H3068"))

        let v = StudyLink.verse(book: 43, chapter: 3, verse: 16, verseEnd: 18)
        let url2 = v.toURL()!
        XCTAssertEqual(StudyLink.from(url: url2), v)
    }

    func testDoesNotLinkNoiseWords() {
        let plain = "See ch 3:4 and cf 1:2 in the notes."
        let links = StudyLinkParser.findLinks(in: plain)
        let verses = links.compactMap { link -> String? in
            if case .verse = link { return "v" }
            return nil
        }
        XCTAssertTrue(verses.isEmpty, "should not link ch/cf noise: \(links)")
    }
}
