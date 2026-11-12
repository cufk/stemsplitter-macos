import Foundation
import Testing
@testable import StemSplitterCore

struct StemLocatorTests {
    @Test func locatesStemsRecursively() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("stemlocator-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("htdemucs/min-lat", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        for name in ["vocals.wav", "drums.wav", "bass.wav", "other.wav", "notes.txt"] {
            fm.createFile(atPath: nested.appendingPathComponent(name).path, contents: Data())
        }

        let found = try StemLocator.locate(in: root)
        #expect(found.count == 4)
        #expect(found[.vocals]?.lastPathComponent == "vocals.wav")
        #expect(found[.drums]?.lastPathComponent == "drums.wav")
        #expect(found[.bass]?.lastPathComponent == "bass.wav")
        #expect(found[.other]?.lastPathComponent == "other.wav")
    }

    @Test func emptyDirectoryReturnsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stemlocator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(try StemLocator.locate(in: root).isEmpty)
    }
}
