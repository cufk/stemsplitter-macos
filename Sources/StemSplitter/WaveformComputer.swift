import AVFoundation

enum WaveformComputer {
    static func peaks(for url: URL, bucketCount: Int = 160) async -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)
        guard let buffer else { return [] }
        var buckets = [Float](repeating: 0, count: bucketCount)
        let total: AVAudioFramePosition = AVAudioFramePosition(max(1, file.length))

        while file.framePosition < total {
            try? file.read(into: buffer, frameCount: 4096)
            let read = buffer.frameLength
            if read == 0 { break }
            guard let data = buffer.floatChannelData else { break }
            let base = file.framePosition - AVAudioFramePosition(read)
            let samples = data[0]
            for i in 0..<Int(read) {
                let frame = base + AVAudioFramePosition(i)
                let index = min(bucketCount - 1, Int(Double(frame) / Double(total) * Double(bucketCount)))
                buckets[index] = max(buckets[index], abs(samples[i]))
            }
            await Task.yield()
        }
        return buckets
    }
}
