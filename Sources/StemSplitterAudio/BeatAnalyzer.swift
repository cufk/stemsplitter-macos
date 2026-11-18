import AVFoundation
import StemSplitterCore

public enum BeatAnalyzer {
    /// Analyserar tempo, slag och taktettor i en ljudfil (bäst på trumspåret).
    /// Läser filen i block och mixar till mono. Returnerar nil om inget tydligt tempo hittas.
    public static func analyze(url: URL) async -> BeatGrid? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536)
        else { return nil }
        var detector = OnsetDetector(sampleRate: file.processingFormat.sampleRate)
        var mono = [Float](repeating: 0, count: Int(buffer.frameCapacity))

        while file.framePosition < file.length {
            if Task.isCancelled { return nil }
            do {
                try file.read(into: buffer, frameCount: buffer.frameCapacity)
            } catch {
                break
            }
            let count = Int(buffer.frameLength)
            guard count > 0, let data = buffer.floatChannelData else { break }
            let channels = Int(buffer.format.channelCount)
            let scale = 1 / Float(channels)
            for i in 0..<count {
                var sum: Float = 0
                for channel in 0..<channels { sum += data[channel][i] }
                mono[i] = sum * scale
            }
            mono.withUnsafeBufferPointer { pointer in
                detector.add(UnsafeBufferPointer(rebasing: pointer[0..<count]))
            }
            await Task.yield()
        }
        return BeatTracker.analyze(onsets: detector.onsets, lowOnsets: detector.lowFlux, frameRate: detector.frameRate)
    }
}
