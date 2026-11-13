import Testing
@testable import StemSplitterCore

struct ProgressParserTests {
    @Test func parsesPercent() {
        #expect(ProgressParser.fraction(fromLine: "  42% klart") == 0.42)
        #expect(ProgressParser.fraction(fromLine: "100%") == 1.0)
        #expect(ProgressParser.fraction(fromLine: "0%") == 0.0)
    }

    @Test func clampsOutOfRange() {
        #expect(ProgressParser.fraction(fromLine: "250%") == 1.0)
    }

    @Test func returnsNilWithoutPercent() {
        #expect(ProgressParser.fraction(fromLine: "laddar modell...") == nil)
        #expect(ProgressParser.fraction(fromLine: "") == nil)
    }

    @Test func parsesMegabyteProgress() {
        #expect(ProgressParser.fraction(fromLine: "  ━━━ 63.9/63.9 MB 8.7 MB/s  0:00:07") == 1.0)
        let mb = ProgressParser.fraction(fromLine: "  32.0/63.9 MB 5.6 MB/s") ?? -1
        #expect(abs(mb - 0.5) < 0.01)
    }
}
