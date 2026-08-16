import XCTest
@testable import Espada

/// Every abbreviation below was harvested from the `<ref>` tags actually present in the
/// installed module library (195 distinct tokens across 1.66 M rows). The ones here were
/// unresolvable, which left their references untappable in the cross-reference sheet —
/// `Jua` and `Apo` alone account for roughly 240 000 references.
final class BibleBookAliasTests: XCTestCase {

    func testHighVolumeSpanishAbbreviationsResolve() {
        // Counts are occurrences in the installed library.
        let cases: [(String, Int, Int)] = [
            ("Jua", 43, 149_256),   // Juan
            ("Apo", 66, 80_316),    // Apocalipsis
            ("Ose", 28, 18_168),    // Oseas
        ]
        for (token, book, _) in cases {
            XCTAssertEqual(BibleBooks.resolveBook(token), book, "\(token) should resolve to book \(book)")
        }
    }

    func testRemainingUnresolvedAbbreviationsResolve() {
        let cases: [(String, Int)] = [
            ("Son", 22),   // Song of Solomon → Cantares
            ("Rth", 8),    // Ruth → Rut
            ("Ats", 44),   // Atos → Hechos
            ("Age", 37),   // Ageo → Hageo
            ("Slm", 19),   // Salmos
            ("Nee", 16),   // Neemías → Nehemías
            ("Ams", 30),   // Amós
            ("Tgo", 59),   // Tiago → Santiago
            ("Jzs", 7),    // Juízes → Jueces
            ("Efs", 49),   // Efesios
        ]
        for (token, book) in cases {
            XCTAssertEqual(BibleBooks.resolveBook(token), book, "\(token) should resolve to book \(book)")
        }
    }

    /// Resolution folds case, so the lowercase spellings modules also use come free.
    func testAbbreviationsResolveCaseInsensitively() {
        for token in ["jua", "JUA", "apo", "APO", "ose", "rth", "ats"] {
            XCTAssertNotNil(BibleBooks.resolveBook(token), "\(token) should resolve")
        }
    }

    /// New aliases must not collide with books that already resolved correctly.
    func testExistingResolutionsAreUnchanged() {
        let cases: [(String, Int)] = [
            ("Gén", 1), ("Éxo", 2), ("Jos", 6), ("Rut", 8), ("Sal", 19), ("Ecl", 21),
            ("Cnt", 22), ("Isa", 23), ("Os", 28), ("Am", 30), ("Hag", 37),
            ("Mat", 40), ("Mar", 41), ("Luc", 42), ("Jn", 43), ("Hch", 44),
            ("Rom", 45), ("1Co", 46), ("2Co", 47), ("Ef", 49), ("Stg", 59),
            ("1Jn", 62), ("2Jn", 63), ("3Jn", 64), ("Jud", 65), ("Ap", 66),
        ]
        for (token, book) in cases {
            XCTAssertEqual(BibleBooks.resolveBook(token), book, "\(token) regressed")
        }
    }

    /// Deuterocanonical books are outside the 66-book model this app uses, so they must
    /// keep returning nil rather than being mapped onto a canonical neighbour.
    func testDeuterocanonicalAbbreviationsStayUnresolved() {
        for token in ["Sir", "Sab", "1Ma", "2Ma", "Tob", "Bar", "Jdt", "Eco", "Wis"] {
            XCTAssertNil(BibleBooks.resolveBook(token), "\(token) must not map to a canonical book")
        }
    }

    /// End to end: a reference using the new aliases becomes a tappable link.
    func testReferencesWithNewAliasesBecomeLinks() {
        let plain = ESwordText.moduleFieldToPlain(
            "<ref>Jua 3:16</ref>; <ref>Apo 22:1</ref>; <ref>Ose 11:8</ref>; <ref>Rth 4:11</ref>."
        )
        let verses = StudyLinkParser.findLinks(in: plain).compactMap { link -> Int? in
            if case .verse(let book, _, _, _) = link { return book }
            return nil
        }
        XCTAssertEqual(verses, [43, 66, 28, 8], "got \(verses) from: \(plain)")
    }
}
