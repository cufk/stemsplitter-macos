import AVFoundation
import StemSplitterCore

enum WaveformComputer {
    /// Toppvärden för vågformen, över alla kanaler. Läser i stora block för fart.
    static func peaks(for url: URL, bucketCount: Int = 400) async -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536)
        else { return [] }
        var accumulator = PeakAccumulator(totalFrames: file.length, bucketCount: bucketCount)
        var position: Int64 = 0
        while position < file.length {
            if Task.isCancelled { return [] }
            do {
                try file.read(into: buffer, frameCount: buffer.frameCapacity)
            } catch {
                break
            }
            let count = Int(buffer.frameLength)
            guard count > 0, let data = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                accumulator.add(UnsafeBufferPointer(start: data[channel], count: count), startFrame: position)
            }
            position += Int64(count)
        }
        return accumulator.peaks
    }
}
