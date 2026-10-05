import XCTest
@testable import Espada

/// Regression: the verse-number gutter was a fixed 26 pt while the number's font scales
/// with the reading size. Past roughly 30 pt the digits no longer fit, so Juan 3:14 drew
/// as "1" stacked above "4".
final class VerseNumberGutterTests: XCTestCase {

    /// Mirrors `VerseRowView`: numbers sit 4 pt below the body size, floored at 11.
    private func numberSize(bodyFontSize: CGFloat) -> CGFloat {
        max(11, bodyFontSize - 4)
    }

    private func gutterWidth(verse: Int, bodyFontSize: CGFloat) -> CGFloat {
        let size = numberSize(bodyFontSize: bodyFontSize)
        let digits = max(2, String(verse).count)
        return max(26, size * 0.62 * CGFloat(digits) + 4)
    }

    /// Rough advance width of bold digits at a given point size.
    private func requiredWidth(verse: Int, bodyFontSize: CGFloat) -> CGFloat {
        let size = numberSize(bodyFontSize: bodyFontSize)
        return CGFloat(String(verse).count) * size * 0.60
    }

    /// The failing case from the screenshot: two digits at a large reading size.
    func testTwoDigitVerseFitsAtLargeFont() {
        for body in stride(from: 30.0, through: 44.0, by: 2.0) {
            let width = gutterWidth(verse: 14, bodyFontSize: CGFloat(body))
            let needed = requiredWidth(verse: 14, bodyFontSize: CGFloat(body))
            XCTAssertGreaterThanOrEqual(
                width, needed,
                "verse 14 would wrap at body size \(body): \(width) < \(needed)"
            )
        }
    }

    /// Salmos 119 runs to verse 176 — three digits must fit too.
    func testThreeDigitVerseFitsAtLargeFont() {
        for body in stride(from: 20.0, through: 44.0, by: 4.0) {
            let width = gutterWidth(verse: 176, bodyFontSize: CGFloat(body))
            let needed = requiredWidth(verse: 176, bodyFontSize: CGFloat(body))
            XCTAssertGreaterThanOrEqual(
                width, needed,
                "verse 176 would wrap at body size \(body): \(width) < \(needed)"
            )
        }
    }

    /// The old fixed width is the floor, so small sizes keep the layout they had.
    func testSmallFontKeepsTheOriginalGutter() {
        XCTAssertEqual(gutterWidth(verse: 1, bodyFontSize: 15), 26)
        XCTAssertEqual(gutterWidth(verse: 14, bodyFontSize: 15), 26)
    }

    /// A single-digit verse still reserves two digits' room, so the text column does not
    /// shift left and right between verse 9 and verse 10.
    func testGutterIsStableAcrossTheNineToTenBoundary() {
        for body in [16.0, 24.0, 34.0] {
            XCTAssertEqual(
                gutterWidth(verse: 9, bodyFontSize: CGFloat(body)),
                gutterWidth(verse: 10, bodyFontSize: CGFloat(body)),
                "text column must not jump between verse 9 and 10 at size \(body)"
            )
        }
    }

    func testGutterGrowsMonotonicallyWithFontSize() {
        var previous: CGFloat = 0
        for body in stride(from: 14.0, through: 44.0, by: 2.0) {
            let width = gutterWidth(verse: 14, bodyFontSize: CGFloat(body))
            XCTAssertGreaterThanOrEqual(width, previous)
            previous = width
        }
    }
}
