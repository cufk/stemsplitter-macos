import AVFoundation
import Foundation
import Testing
@testable import StemSplitterAudio

struct BeatAnalyzerTests {
    /// Skriver en stereo-WAV med kickar (avklingande 70 Hz) i ett givet tempo.
    private func writeKicks(to url: URL, bpm: Double, seconds: Double, sampleRate: Double = 44100) throws -> [Double] {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        var times: [Double] = []
        var t = 0.3
        while t < seconds - 0.1 {
            times.append(t)
            let first = Int(t * sampleRate)
            for i in 0..<Int(0.08 * sampleRate) {
                let tt = Double(i) / sampleRate
                let value = Float(0.8 * sin(2 * Double.pi * 70 * tt) * exp(-tt / 0.03))
                buffer.floatChannelData![0][first + i] += value
                buffer.floatChannelData![1][first + i] += value
            }
            t += 60 / bpm
        }
        let file = try AVAudioFile(forWriting: url, settings: format.fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        return times
    }

    @Test(.timeLimit(.minutes(1)))
    func findsTempoInAudioFile() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("drums.wav")
        let times = try writeKicks(to: url, bpm: 124, seconds: 12)

        let grid = try #require(await BeatAnalyzer.analyze(url: url))

        #expect(abs(grid.bpm - 124) < 0.5)
        #expect(grid.beats.count == times.count)
        #expect(abs(grid.beats[0] - times[0]) < 0.015)
    }

    @Test func missingFileGivesNil() async {
        #expect(await BeatAnalyzer.analyze(url: URL(fileURLWithPath: "/finns/inte.wav")) == nil)
    }
}
