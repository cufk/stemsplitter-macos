import Foundation
import Testing
@testable import StemSplitterCore

struct CacheKeyTests {
    @Test func fnv1aMatchesReferenceValue() {
        // Referensvärde för FNV-1a 64 av "a"
        #expect(CacheKey.fnv1a(Array("a".utf8)) == 0xaf63dc4c8601ec8c)
    }

    @Test func sameContentSameKeyRegardlessOfPath() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("cachekey-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let bytes = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let a = dir.appendingPathComponent("a.wav")
        let b = dir.appendingPathComponent("flyttad.wav")
        try bytes.write(to: a)
        try bytes.write(to: b)
        #expect(try CacheKey.fingerprint(of: a) == CacheKey.fingerprint(of: b))
    }

    @Test func differentContentDifferentKey() {
        let one = CacheKey.fingerprint(size: 10, head: [1, 2, 3], tail: [])
        let two = CacheKey.fingerprint(size: 10, head: [1, 2, 4], tail: [])
        let three = CacheKey.fingerprint(size: 11, head: [1, 2, 3], tail: [])
        #expect(one != two)
        #expect(one != three)
        #expect(one.count == 16)
    }
}
