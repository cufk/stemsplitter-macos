import XCTest
@testable import StemSplitterCore

final class TimeFormatTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(TimeFormat.format(0), "0:00")
        XCTAssertEqual(TimeFormat.format(9.4), "0:09")
        XCTAssertEqual(TimeFormat.format(65), "1:05")
        XCTAssertEqual(TimeFormat.format(3599.6), "60:00")
        XCTAssertEqual(TimeFormat.format(-5), "0:00")
        XCTAssertEqual(TimeFormat.format(.infinity), "0:00")
    }
}
