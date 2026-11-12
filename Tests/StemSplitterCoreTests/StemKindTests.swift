import XCTest
@testable import StemSplitterCore

final class StemKindTests: XCTestCase {
    func testParsesKnownStemFileNames() {
        XCTAssertEqual(StemKind(fileName: "vocals.wav"), .vocals)
        XCTAssertEqual(StemKind(fileName: "drums.wav"), .drums)
        XCTAssertEqual(StemKind(fileName: "bass.wav"), .bass)
        XCTAssertEqual(StemKind(fileName: "other.wav"), .other)
    }

    func testIsCaseInsensitiveAndIgnoresExtension() {
        XCTAssertEqual(StemKind(fileName: "Vocals.WAV"), .vocals)
        XCTAssertEqual(StemKind(fileName: "OTHER.mp3"), .other)
    }

    func testRejectsUnknownNames() {
        XCTAssertNil(StemKind(fileName: "no_vocals.wav"))
        XCTAssertNil(StemKind(fileName: "README.md"))
        XCTAssertNil(StemKind(fileName: "vocals2.wav"))
    }

    func testDisplayNames() {
        XCTAssertEqual(StemKind.vocals.displayName, "Sång")
        XCTAssertEqual(StemKind.drums.displayName, "Trummor")
        XCTAssertEqual(StemKind.bass.displayName, "Bas")
        XCTAssertEqual(StemKind.other.displayName, "Övrigt")
    }
}
