import Foundation

/// Samlar toppvärden (max |sample|) i ett fast antal hinkar för vågformsvisning.
public struct PeakAccumulator {
    public private(set) var peaks: [Float]
    public let totalFrames: Int64

    public init(totalFrames: Int64, bucketCount: Int) {
        self.totalFrames = max(1, totalFrames)
        self.peaks = [Float](repeating: 0, count: max(1, bucketCount))
    }

    /// Lägg till samples för en kanal som börjar på `startFrame`. Anropa en gång per kanal.
    public mutating func add(_ samples: UnsafeBufferPointer<Float>, startFrame: Int64) {
        let buckets = Int64(peaks.count)
        let last = peaks.count - 1
        for i in 0..<samples.count {
            let frame = startFrame + Int64(i)
            let index = min(last, max(0, Int(frame * buckets / totalFrames)))
            let value = abs(samples[i])
            if value > peaks[index] {
                peaks[index] = value
            }
        }
    }

    public mutating func add(_ samples: [Float], startFrame: Int64) {
        samples.withUnsafeBufferPointer { add($0, startFrame: startFrame) }
    }
}
