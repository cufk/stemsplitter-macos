import XCTest
@testable import StemSplitterCore

final class AudioFileSupportTests: XCTestCase {
    func testSupportedExtensions() {
        XCTAssertTrue(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.wav")))
        XCTAssertTrue(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.MP3")))
        XCTAssertTrue(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.Flac")))
        XCTAssertFalse(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.txt")))
        XCTAssertFalse(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.ogg")))
    }
}
