import XCTest
@testable import Espada

/// Samples are verbatim `Comments` fields from the installed modules:
/// `02RC-TCBe.cmti` (Spanish Treasury of Scripture Knowledge) and
/// `02RVR1960x.cmti` (Reina Valera 1960 con títulos, notas y referencias).
final class CrossReferenceFilterTests: XCTestCase {

    private func entry(_ raw: String, label: String = "v.16") -> StudyEntry {
        StudyEntry(
            scope: "verse",
            label: label,
            plain: ESwordText.moduleFieldToPlain(raw),
            html: ""
        )
    }

    /// A dedicated cross-reference module is nothing but `<ref>` chains — every entry
    /// must survive the filter untouched.
    func testTreasuryEntriesAreAllKept() {
        let raw = "<ref>Gén 22:12</ref>; <ref>Mat 9:13</ref>; <ref>Jua 1:14</ref>; <ref>Rom 5:8</ref>; <ref>1Jn 4:9-10</ref>."
        let kept = StudySession.entriesContainingReferences([entry(raw)])
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].plain.contains("Gén 22:12"), kept[0].plain)
        XCTAssertTrue(kept[0].plain.contains("1Jn 4:9-10"), kept[0].plain)
    }

    /// The bug: Juan 3:16 in RVR1960x is a section heading, and it was being presented in
    /// the cross-reference sheet as though it were a reference.
    func testSectionHeadingIsNotACrossReference() {
        let raw = #"<p><b><i>Tema:</i></b></p><p style="text-align:center;"><b>De tal manera amó Dios al mundo</b></p>"#
        XCTAssertTrue(StudySession.entriesContainingReferences([entry(raw)]).isEmpty)
    }

    func testOtherHeadingsAreAlsoDropped() {
        for raw in [
            #"<p><b><i>Tema:</i></b></p><p style="text-align:center;"><b>La creación</b></p>"#,
            #"<p><b><i>Tema:</i></b></p><p style="text-align:center;"><b>Jehová es mi pastor</b></p><p style="text-align:center;"><i>Salmo de David.</i></p>"#,
            #"<p><b><i>Tema:</i></b></p><p style="text-align:center;"><b>Más que vencedores</b></p>"#,
        ] {
            XCTAssertTrue(
                StudySession.entriesContainingReferences([entry(raw)]).isEmpty,
                "kept a heading: \(ESwordText.moduleFieldToPlain(raw))"
            )
        }
    }

    /// Génesis 1:3 in the same module *does* carry a footnote reference, so it stays.
    func testFootnoteReferenceInStudyBibleApparatusIsKept() {
        let raw = #"<p>Y dijo Dios: Sea la luz;<span style="color:#804DB3;font-style:italic;"><sup>a</sup></span> y fue la luz.</p><p><span style="color:#804DB3;font-style:italic;"><sup>a</sup></span> <ref>2Co 4:6</ref>.</p>"#
        let kept = StudySession.entriesContainingReferences([entry(raw, label: "v.3")])
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].plain.contains("2Co 4:6"), kept[0].plain)
    }

    /// A parallel-passage heading is a genuine cross-reference and must be kept.
    func testParallelPassageHeadingIsKept() {
        let raw = #"<p><b><i>Tema:</i></b></p><p style="text-align:center;"><b>Genealogía de Jesucristo</b></p><p style="text-align:center;"><b>(Lc. 3.23–38)</b></p>"#
        XCTAssertEqual(StudySession.entriesContainingReferences([entry(raw, label: "v.1")]).count, 1)
    }

    /// Mixed input: only the reference-bearing entries come through, in order.
    func testFilterKeepsOrderAndDropsOnlyReferencelessEntries() {
        let heading = entry(#"<p><b>Tema:</b></p><p><b>La creación</b></p>"#, label: "1:1–1:31")
        let withRef = entry("<ref>2Co 4:6</ref>.", label: "v.3")
        let prose = entry("<p>Nota del editor sin ninguna cita.</p>", label: "v.4")
        let kept = StudySession.entriesContainingReferences([heading, withRef, prose])
        XCTAssertEqual(kept.map(\.label), ["v.3"])
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(StudySession.entriesContainingReferences([]).isEmpty)
    }

    // MARK: - Numbered books

    /// Regression: `isMorphologyCode` classified any letter+digit mix as morphology, so
    /// every numbered book was deleted from reference lists — `1Jn 4:9-10` arrived as
    /// `4:9-10`, unresolvable and untappable.
    func testNumberedBooksSurviveTextCleaning() {
        let raw = "<ref>1Jn 4:9-10</ref>; <ref>2Co 5:19-21</ref>; <ref>1Ti 1:15-16</ref>; <ref>2Re 8:24</ref>; <ref>3Jn 1:4</ref>."
        let plain = ESwordText.moduleFieldToPlain(raw)
        for ref in ["1Jn 4:9-10", "2Co 5:19-21", "1Ti 1:15-16", "2Re 8:24", "3Jn 1:4"] {
            XCTAssertTrue(plain.contains(ref), "lost «\(ref)» from: \(plain)")
        }
    }

    func testNumberedBooksAreNotMorphologyCodes() {
        for book in ["1Jn", "2Co", "1Ti", "2Ti", "1Pe", "2Pe", "3Jn", "1Cr", "2Cr", "1Re", "2Re", "1Sa", "2Sa"] {
            XCTAssertFalse(StrongResolve.isMorphologyCode(book), "\(book) treated as morphology")
        }
        // The rule this sits next to must still catch real morphology.
        for morph in ["VqAmSM3", "vaw3ms", "NPDSMN", "VtMISM2"] {
            XCTAssertTrue(StrongResolve.isMorphologyCode(morph), "\(morph) no longer detected")
        }
    }

    /// Every reference in a real TSK entry has to survive and stay linkable.
    func testFullTreasuryEntryKeepsEveryReference() {
        let raw = "<ref>Gén 22:12</ref>; <ref>Mat 9:13</ref>; <ref>Mar 12:6</ref>; <ref>Luc 2:14</ref>; <ref>Jua 1:14</ref>; <ref>Rom 5:8</ref>; <ref>Rom 8:32</ref>; <ref>2Co 5:19-21</ref>; <ref>1Ti 1:15-16</ref>; <ref>Tit 3:4</ref>; <ref>1Jn 4:9-10</ref>; <ref>1Jn 4:19</ref>."
        let plain = ESwordText.moduleFieldToPlain(raw)
        let links = StudyLinkParser.findLinks(in: plain).filter {
            if case .verse = $0 { return true }
            return false
        }
        XCTAssertEqual(links.count, 12, "expected every reference to resolve: \(plain)")
    }
}
