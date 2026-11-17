import AVFoundation
import Foundation
import Testing
@testable import StemSplitterAudio

struct StemResidualTests {
    private func write(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<2 {
            for (i, value) in samples.enumerated() { buffer.floatChannelData![channel][i] = value }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    @Test func otherBecomesEverythingElse() throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let count = 100_000
        let mix = (0..<count).map { Float(sin(Double($0) * 0.01) * 0.6) }
        let vocals = mix.map { $0 * 0.5 }
        let drums = mix.map { $0 * 0.2 }
        let bass = mix.map { $0 * 0.1 }
        let other = mix.map { $0 * 0.1 }   // Demucs "tappade" 10 % av mixen
        let urls = ["mix", "vocals", "drums", "bass", "other"].map { dir.appendingPathComponent("\($0).wav") }
        for (samples, url) in zip([mix, vocals, drums, bass, other], urls) { try write(samples, to: url) }

        let report = try StemResidual.rebuild(target: urls[4], mix: urls[0], subtract: Array(urls[1...3]))

        let rebuilt = try read(urls[4])
        #expect(rebuilt.count == count)
        for i in stride(from: 0, to: count, by: 997) {
            #expect(abs(vocals[i] + drums[i] + bass[i] + rebuilt[i] - mix[i]) < 1e-5)
        }
        // Det saknade var 10 % av amplituden ≈ −20 dB
        #expect(abs(report.missingLevel - (-20)) < 0.5)
        // Inga temporära filer kvar
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".") }.isEmpty)
    }
}
