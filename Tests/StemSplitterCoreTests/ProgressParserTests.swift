import XCTest
@testable import StemSplitterCore

final class ProgressParserTests: XCTestCase {
    func testParsesPercent() {
        XCTAssertEqual(ProgressParser.fraction(fromLine: "  42% klart"), 0.42, accuracy: 1e-9)
        XCTAssertEqual(ProgressParser.fraction(fromLine: "100%"), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ProgressParser.fraction(fromLine: "0%"), 0.0, accuracy: 1e-9)
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(ProgressParser.fraction(fromLine: "250%"), 1.0, accuracy: 1e-9)
    }

    func testReturnsNilWithoutPercent() {
        XCTAssertNil(ProgressParser.fraction(fromLine: "laddar modell..."))
        XCTAssertNil(ProgressParser.fraction(fromLine: ""))
    }
}
