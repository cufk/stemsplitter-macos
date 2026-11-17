import Foundation

/// Cache-nyckel baserad på filens innehåll (storlek + första och sista MB),
/// så att samma låt känns igen även om den flyttas eller byter namn.
public enum CacheKey {
    public static let sampleBytes = 1 << 20

    public static func fnv1a<S: Sequence>(_ bytes: S, seed: UInt64 = 0xcbf29ce484222325) -> UInt64 where S.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }

    public static func fingerprint(size: Int64, head: [UInt8], tail: [UInt8]) -> String {
        var hash = fnv1a(Array("v2|\(size)|".utf8))
        hash = fnv1a(head, seed: hash)
        hash = fnv1a([0x7C], seed: hash)
        hash = fnv1a(tail, seed: hash)
        return String(format: "%016llx", hash)
    }

    public static func fingerprint(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int64(try handle.seekToEnd())
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: sampleBytes) ?? Data()
        var tail = Data()
        if size > Int64(sampleBytes) {
            try handle.seek(toOffset: UInt64(size - Int64(sampleBytes)))
            tail = try handle.read(upToCount: sampleBytes) ?? Data()
        }
        return fingerprint(size: size, head: [UInt8](head), tail: [UInt8](tail))
    }
}
