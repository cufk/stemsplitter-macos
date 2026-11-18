import Testing
@testable import StemSplitterCore

struct TransportTests {
    @Test func clampKeepsWithinDuration() {
        #expect(Transport.clamp(-3, duration: 100) == 0)
        #expect(Transport.clamp(150, duration: 100) == 100)
        #expect(Transport.clamp(.nan, duration: 100) == 0)
    }

    @Test func skipMovesAndClamps() {
        #expect(Transport.skip(from: 10, by: 5, duration: 100) == 15)
        #expect(Transport.skip(from: 2, by: -5, duration: 100) == 0)
        #expect(Transport.skip(from: 98, by: 5, duration: 100) == 100)
    }

    @Test func resumeFromEndRestarts() {
        #expect(Transport.resumePosition(100, duration: 100) == 0)
        #expect(Transport.resumePosition(42, duration: 100) == 42)
    }

    @Test func pausedPositionIsKeptWhenResuming() {
        // Regression: paus satte tidigare positionen till slutet så att play började om från 0
        let paused = Transport.position(startOffset: 30, renderedFrames: 441_000, sampleRate: 44100, duration: 200)
        #expect(paused == 40)
        #expect(Transport.resumePosition(paused, duration: 200) == 40)
    }

    @Test func segmentFromOffset() {
        let seg = Transport.segment(offset: 1, sampleRate: 44100, length: 441_000)
        #expect(seg?.start == 44100)
        #expect(seg?.count == 396_900)
    }

    @Test func segmentPastEndIsNil() {
        #expect(Transport.segment(offset: 20, sampleRate: 44100, length: 441_000) == nil)
        #expect(Transport.segment(offset: 0, sampleRate: 44100, length: 0) == nil)
    }

    @Test func positionIgnoresFramesBeforeStart() {
        // Före den schemalagda starttiden är sampleTime negativt
        #expect(Transport.position(startOffset: 5, renderedFrames: -2048, sampleRate: 44100, duration: 60) == 5)
    }
}
