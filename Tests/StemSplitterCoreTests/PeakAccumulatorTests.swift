import Testing
@testable import StemSplitterCore

struct PeakAccumulatorTests {
    @Test func bucketsHoldAbsolutePeaks() {
        var acc = PeakAccumulator(totalFrames: 8, bucketCount: 4)
        acc.add([0.1, -0.5, 0.2, 0.3, -0.9, 0.0, 0.4, 0.05], startFrame: 0)
        #expect(acc.peaks == [0.5, 0.3, 0.9, 0.4])
    }

    @Test func chunksAndChannelsCombine() {
        var acc = PeakAccumulator(totalFrames: 4, bucketCount: 2)
        acc.add([0.1, 0.2], startFrame: 0)   // vänster kanal, första chunk
        acc.add([-0.7, 0.0], startFrame: 0)  // höger kanal, första chunk
        acc.add([0.3, 0.6], startFrame: 2)   // andra chunk
        #expect(acc.peaks == [0.7, 0.6])
    }

    @Test func framesBeyondTotalGoToLastBucket() {
        var acc = PeakAccumulator(totalFrames: 2, bucketCount: 2)
        acc.add([0, 0, 0.8], startFrame: 0)
        #expect(acc.peaks.last == 0.8)
    }
}
