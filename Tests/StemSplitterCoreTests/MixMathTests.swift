import Testing
@testable import StemSplitterCore

struct MixMathTests {
    @Test func mixChannelsAppliesGainsAndSums() {
        let a: [Float] = [1, -1, 0.5]
        let b: [Float] = [0.5, 0.5, -0.5]
        let mixed = MixMath.mixChannels([(a, 2.0), (b, 1.0)], count: 3)
        #expect(mixed == [2.5, -1.5, 0.5])
    }

    @Test func mixChannelsShorterInputIsZeroPadded() {
        let mixed = MixMath.mixChannels([([1.0], 1.0)], count: 3)
        #expect(mixed == [1.0, 0.0, 0.0])
    }

    @Test func clampLimitsValues() {
        #expect(MixMath.clamp([2.0, -3.0, 0.25]) == [1.0, -1.0, 0.25])
    }

    @Test func pointerHelpersMatchArrayVersions() {
        let input: [Float] = [0.2, -0.4, 0.9, 1.7]
        var gained = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            gained.withUnsafeMutableBufferPointer { dst in
                MixMath.applyGain(src.baseAddress!, dst.baseAddress!, count: src.count, gain: 2.0)
            }
        }
        #expect(gained == MixMath.mixChannels([(input, 2.0)], count: input.count))

        var acc = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            acc.withUnsafeMutableBufferPointer { dst in
                MixMath.accumulate(src.baseAddress!, dst.baseAddress!, count: src.count)
            }
        }
        #expect(acc == input)

        var clipped = [3.0, -5.0, 0.5]
        clipped.withUnsafeMutableBufferPointer { ptr in
            MixMath.clampChannel(ptr.baseAddress!, count: clipped.count)
        }
        #expect(clipped == [1.0, -1.0, 0.5])
    }

    @Test func zeroFillsBuffer() {
        var buffer = [Float](repeating: 9, count: 4)
        buffer.withUnsafeMutableBufferPointer { ptr in
            MixMath.zero(ptr.baseAddress!, count: buffer.count)
        }
        #expect(buffer == [0, 0, 0, 0])
    }
}
