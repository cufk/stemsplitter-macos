import Foundation
import Testing
@testable import StemSplitterCore

struct ProjectMetaTests {
    @Test func roundTripsThroughJSON() throws {
        let meta = ProjectMeta(
            sourceName: "Min låt.mp3",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            model: "htdemucs",
            peaks: ["vocals": [0.1, 0.5], "bass": [0.25]]
        )
        let decoded = try ProjectMeta.decode(meta.encoded())
        #expect(decoded == meta)
        #expect(decoded.peaks(for: .vocals) == [0.1, 0.5])
        #expect(decoded.peaks(for: .drums) == nil)
    }

    @Test func displayNameDropsExtension() {
        let meta = ProjectMeta(sourceName: "Övningslåt.m4a", createdAt: Date(), model: "htdemucs")
        #expect(meta.displayName == "Övningslåt")
    }
}
