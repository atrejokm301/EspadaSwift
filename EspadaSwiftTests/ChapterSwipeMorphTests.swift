import XCTest
@testable import Espada

final class ChapterSwipeMorphTests: XCTestCase {

    func testSwipeLeftCommitsNext() {
        // Finger moves right → left (negative width) = next chapter.
        let d = ChapterSwipeDecision.resolve(translation: CGSize(width: -90, height: 10))
        XCTAssertEqual(d, .next)
    }

    func testSwipeRightCommitsPrevious() {
        // Finger moves left → right (positive width) = previous chapter.
        let d = ChapterSwipeDecision.resolve(translation: CGSize(width: 90, height: 8))
        XCTAssertEqual(d, .previous)
    }

    func testShortDragDoesNotCommit() {
        let d = ChapterSwipeDecision.resolve(translation: CGSize(width: 40, height: 0))
        XCTAssertEqual(d, .none)
    }

    func testVerticalScrollDominates() {
        // Tall vertical drag with some horizontal noise must not change chapter.
        let d = ChapterSwipeDecision.resolve(translation: CGSize(width: 80, height: 120))
        XCTAssertEqual(d, .none)
    }

    func testHorizontalDominanceAllowsSlightVerticalNoise() {
        // Finger left with small vertical noise → next.
        let d = ChapterSwipeDecision.resolve(translation: CGSize(width: -100, height: 30))
        XCTAssertEqual(d, .next)
    }

    func testResistedOffsetIsBounded() {
        let far = ChapterSwipeDecision.resistedOffset(400, limit: 140)
        XCTAssertLessThan(abs(far), 141)
        XCTAssertGreaterThan(abs(far), 100)
        XCTAssertEqual(ChapterSwipeDecision.resistedOffset(0), 0, accuracy: 0.001)
        XCTAssertEqual(
            ChapterSwipeDecision.resistedOffset(50),
            -ChapterSwipeDecision.resistedOffset(-50),
            accuracy: 0.001
        )
    }

    func testNotVelocityBased_largeButShortDistanceStillNeedsThreshold() {
        // Even a "fling-like" short translation stays none — distance gate only.
        let d = ChapterSwipeDecision.resolve(translation: CGSize(width: 50, height: 0))
        XCTAssertEqual(d, .none)
    }
}
