import XCTest
import QuartzCore
@testable import Espada

final class ReadingFrameRateTests: XCTestCase {
    func testHighPrefers120Min1Max120() {
        let r = ReadingFrameRate.high
        XCTAssertEqual(r.minimum, 1)
        XCTAssertEqual(r.maximum, 120)
        XCTAssertEqual(r.preferred, 120)
    }

    func testLowPrefers1Min1Max20() {
        let r = ReadingFrameRate.low
        XCTAssertEqual(r.minimum, 1)
        XCTAssertEqual(r.maximum, 20)
        XCTAssertEqual(r.preferred, 1)
    }

    func testAliasesMatch() {
        XCTAssertEqual(ReadingFrameRate.active.preferred, ReadingFrameRate.high.preferred)
        XCTAssertEqual(ReadingFrameRate.idle.preferred, ReadingFrameRate.low.preferred)
    }
}
