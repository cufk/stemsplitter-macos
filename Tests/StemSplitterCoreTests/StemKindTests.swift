import Testing
@testable import StemSplitterCore

struct StemKindTests {
    @Test func parsesKnownStemFileNames() {
        #expect(StemKind(fileName: "vocals.wav") == .vocals)
        #expect(StemKind(fileName: "drums.wav") == .drums)
        #expect(StemKind(fileName: "bass.wav") == .bass)
        #expect(StemKind(fileName: "other.wav") == .other)
    }

    @Test func isCaseInsensitiveAndIgnoresExtension() {
        #expect(StemKind(fileName: "Vocals.WAV") == .vocals)
        #expect(StemKind(fileName: "OTHER.mp3") == .other)
    }

    @Test func rejectsUnknownNames() {
        #expect(StemKind(fileName: "no_vocals.wav") == nil)
        #expect(StemKind(fileName: "README.md") == nil)
        #expect(StemKind(fileName: "vocals2.wav") == nil)
    }

    @Test func displayNames() {
        #expect(StemKind.vocals.displayName == "Sång")
        #expect(StemKind.drums.displayName == "Trummor")
        #expect(StemKind.bass.displayName == "Bas")
        #expect(StemKind.other.displayName == "Övrigt")
    }
}
