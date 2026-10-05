import XCTest
@testable import Espada

/// Padding across the app was written as fixed points chosen at a default text size.
/// Enlarging the reading font grew the text but not the space around it, so lines crowded
/// the screen edge and the last verse could not clear the tab dock.
final class ReadingMetricsTests: XCTestCase {

    /// At or below the baseline the numbers must equal the app's original constants, so
    /// normal-size layouts are byte-identical to before.
    func testBaselineMatchesTheOriginalConstants() {
        for size in [10.0, 14.0, 17.0] as [CGFloat] {
            XCTAssertEqual(ReadingMetrics.horizontalMargin(fontSize: size), 12)
            XCTAssertEqual(ReadingMetrics.rowInset(fontSize: size), 8)
            XCTAssertEqual(ReadingMetrics.cardPadding(fontSize: size), 12)
        }
    }

    func testEveryMetricGrowsWithTheFont() {
        let metrics: [(String, (CGFloat) -> CGFloat)] = [
            ("horizontalMargin", { ReadingMetrics.horizontalMargin(fontSize: $0) }),
            ("rowInset", { ReadingMetrics.rowInset(fontSize: $0) }),
            ("bottomClearance", { ReadingMetrics.bottomClearance(fontSize: $0) }),
            ("topClearance", { ReadingMetrics.topClearance(fontSize: $0) }),
            ("cardPadding", { ReadingMetrics.cardPadding(fontSize: $0) }),
        ]
        for (name, metric) in metrics {
            var previous: CGFloat = -1
            for size in stride(from: 12.0, through: 48.0, by: 3.0) {
                let value = metric(CGFloat(size))
                XCTAssertGreaterThanOrEqual(value, previous, "\(name) shrank at \(size)")
                previous = value
            }
            XCTAssertGreaterThanOrEqual(
                metric(40), metric(17),
                "\(name) must not shrink once the reader enlarges the font"
            )
        }
    }

    /// The real objective: the share of the screen given to furniture rather than text
    /// must stay roughly constant as the font grows.
    ///
    /// Scaling margins and the verse gutter linearly took 30% of an iPhone 17 Pro Max at
    /// 44 pt, against 16% at the default — the reading column became a narrow ribbon with
    /// a conspicuous gap before every line.
    func testFurnitureKeepsAConstantShareOfTheScreen() {
        let screen: CGFloat = 440   // iPhone 17 Pro Max points

        func lostFraction(at body: CGFloat) -> CGFloat {
            let margin = ReadingMetrics.horizontalMargin(fontSize: body)
            let inset = ReadingMetrics.rowInset(fontSize: body)
            let gutter = ReadingMetrics.verseNumberWidth(verse: 3, fontSize: body)
            let spacing: CGFloat = 6
            let text = screen - (margin + inset + gutter + spacing) - (margin + inset)
            return (screen - text) / screen
        }

        let baseline = lostFraction(at: 17)
        for body in stride(from: 17.0, through: 52.0, by: 5.0) {
            let lost = lostFraction(at: CGFloat(body))
            XCTAssertLessThan(lost, 0.25, "furniture takes \(Int(lost * 100))% at \(body) pt")
            XCTAssertLessThan(
                lost - baseline, 0.07,
                "furniture share drifted \(Int((lost - baseline) * 100)) points at \(body) pt"
            )
        }
    }

    /// Verse numbers are marginalia and must not grow proportionally with the prose.
    func testVerseNumberStaysSubordinateToTheText() {
        XCTAssertEqual(ReadingMetrics.verseNumberSize(fontSize: 17), 13, "default is unchanged")
        for body in [30.0, 40.0, 52.0] as [CGFloat] {
            let ratio = ReadingMetrics.verseNumberSize(fontSize: body) / body
            XCTAssertLessThan(ratio, 0.60, "verse number is competing with the text at \(body) pt")
            XCTAssertGreaterThan(ratio, 0.35, "verse number is too faint to hit at \(body) pt")
        }
    }

    /// A font size fed to `Font.custom` must stay in stored units, or the system
    /// multiplier gets applied twice and the verse number renders enormous.
    func testVerseNumberSizeIsNotDoubleScaled() {
        // At the default system text size the two are equal; the guard is that this
        // value is never pre-multiplied before reaching the font.
        XCTAssertEqual(ReadingMetrics.verseNumberSize(fontSize: 17), 13)
        XCTAssertLessThanOrEqual(
            ReadingMetrics.verseNumberSize(fontSize: 44), 44,
            "verse number must never exceed the body size it annotates"
        )
    }

    /// Margins stop growing rather than running away.
    func testSpacingIsCapped() {
        XCTAssertLessThanOrEqual(ReadingMetrics.horizontalMargin(fontSize: 80), 18)
        XCTAssertLessThanOrEqual(ReadingMetrics.rowInset(fontSize: 80), 11)
    }

    /// The last verse has to clear a floating dock roughly 70 pt tall once the reader is
    /// at a large size, where a whole line would otherwise sit behind it.
    func testBottomClearanceCoversTheFloatingDockAtLargeSizes() {
        XCTAssertGreaterThanOrEqual(ReadingMetrics.bottomClearance(fontSize: 40), 48)
        XCTAssertGreaterThan(
            ReadingMetrics.bottomClearance(fontSize: 40),
            ReadingMetrics.bottomClearance(fontSize: 17)
        )
    }

    func testGrowthIsZeroAtOrBelowBaseline() {
        XCTAssertEqual(ReadingMetrics.growth(10), 0)
        XCTAssertEqual(ReadingMetrics.growth(17), 0)
        XCTAssertEqual(ReadingMetrics.growth(20), 3)
    }
}
