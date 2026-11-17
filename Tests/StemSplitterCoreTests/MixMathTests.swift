import Testing
@testable import StemSplitterCore

struct MixMathTests {
    @Test func clampChannelLimitsInPlace() {
        var clipped: [Float] = [3.0, -5.0, 0.5, 1.0]
        let count = clipped.count
        clipped.withUnsafeMutableBufferPointer { ptr in
            MixMath.clampChannel(ptr.baseAddress!, count: count)
        }
        #expect(clipped == [1.0, -1.0, 0.5, 1.0])
    }

    @Test func muteAlwaysSilences() {
        #expect(MixMath.effectiveGain(volume: 1.2, muted: true, soloed: true, anySoloed: true) == 0)
    }

    @Test func soloSilencesOthers() {
        #expect(MixMath.effectiveGain(volume: 0.8, muted: false, soloed: false, anySoloed: true) == 0)
        #expect(MixMath.effectiveGain(volume: 0.8, muted: false, soloed: true, anySoloed: true) == Float(0.8))
    }

    @Test func noSoloUsesVolume() {
        #expect(MixMath.effectiveGain(volume: 1.5, muted: false, soloed: false, anySoloed: false) == Float(1.5))
        #expect(MixMath.effectiveGain(volume: -1, muted: false, soloed: false, anySoloed: false) == 0)
    }

    @Test func outputFrameCountScalesWithTempo() {
        #expect(MixMath.outputFrameCount(sourceDuration: 10, tempo: 1, sampleRate: 44100) == 441_000)
        #expect(MixMath.outputFrameCount(sourceDuration: 10, tempo: 2, sampleRate: 44100) == 220_500)
        #expect(MixMath.outputFrameCount(sourceDuration: 10, tempo: 0.5, sampleRate: 44100) == 882_000)
        #expect(MixMath.outputFrameCount(sourceDuration: 0, tempo: 1, sampleRate: 44100) == 0)
    }

    @Test func semitonesBecomeCents() {
        // AVAudioUnitTimePitch.pitch anges i cent — 1 halvton = 100 cent
        #expect(MixMath.cents(fromSemitones: 1) == 100)
        #expect(MixMath.cents(fromSemitones: -12) == -1200)
        #expect(MixMath.cents(fromSemitones: 99) == 2400)
    }
}
