import XCTest
@testable import StemSplitterCore

final class StemLocatorTests: XCTestCase {
    func testLocatesStemsRecursively() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("stemlocator-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("htdemucs/min-lat", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        for name in ["vocals.wav", "drums.wav", "bass.wav", "other.wav", "notes.txt"] {
            fm.createFile(atPath: nested.appendingPathComponent(name).path, contents: Data())
        }

        let found = try StemLocator.locate(in: root)
        XCTAssertEqual(found.count, 4)
        XCTAssertEqual(found[.vocals]?.lastPathComponent, "vocals.wav")
        XCTAssertEqual(found[.drums]?.lastPathComponent, "drums.wav")
        XCTAssertEqual(found[.bass]?.lastPathComponent, "bass.wav")
        XCTAssertEqual(found[.other]?.lastPathComponent, "other.wav")
    }

    func testEmptyDirectoryReturnsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stemlocator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(try StemLocator.locate(in: root).isEmpty)
    }
}
