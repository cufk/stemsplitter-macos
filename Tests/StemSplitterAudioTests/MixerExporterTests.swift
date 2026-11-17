import AVFoundation
import Foundation
import Testing
@testable import StemSplitterAudio

struct MixerExporterTests {
    private func makeStems(in dir: URL, amplitude: Float, seconds: Double = 1) throws -> [URL] {
        let urls = ["vocals.wav", "drums.wav"].map { dir.appendingPathComponent($0) }
        for (index, url) in urls.enumerated() {
            try TestAudio.writeSine(to: url, sampleRate: 44100, channels: 2, seconds: seconds,
                                    amplitude: amplitude, frequency: 220 * Double(index + 1))
        }
        return urls
    }

    // Regression: exporten låste sig (async scheduleFile) och tog aldrig slut
    // (spelarna ger tystnad efter filslut i offline-läge).
    @Test(.timeLimit(.minutes(1)))
    func exportFinishesWithExpectedLength() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stems = try makeStems(in: dir, amplitude: 0.3).map { MixerExporter.StemInput(url: $0, gain: 1) }
        let output = dir.appendingPathComponent("mix.wav")

        try await MixerExporter.exportMix(stems: stems, to: output, pitchSemitones: 0, tempo: 1) { _ in }

        let file = try AVAudioFile(forReading: output)
        #expect(file.length >= 44100)
        #expect(file.length < 44100 + 8820)  // högst 0,2 s extra för tonhöjdsenhetens latens
    }

    @Test(.timeLimit(.minutes(1)))
    func doubleTempoHalvesLength() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stems = try makeStems(in: dir, amplitude: 0.3, seconds: 2).map { MixerExporter.StemInput(url: $0, gain: 1) }
        let output = dir.appendingPathComponent("mix.wav")

        try await MixerExporter.exportMix(stems: stems, to: output, pitchSemitones: 0, tempo: 2) { _ in }

        let file = try AVAudioFile(forReading: output)
        #expect(file.length >= 44100)
        #expect(file.length < 44100 + 8820)
    }

    @Test(.timeLimit(.minutes(1)))
    func loudMixIsClipped() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 2 × 0,9 × 1,5 ≈ 2,7 före klippning
        let stems = try makeStems(in: dir, amplitude: 0.9).map { MixerExporter.StemInput(url: $0, gain: 1.5) }
        let output = dir.appendingPathComponent("mix.wav")

        try await MixerExporter.exportMix(stems: stems, to: output, pitchSemitones: 0, tempo: 1) { _ in }

        let peaks = try TestAudio.channelPeaks(output)
        #expect(peaks.allSatisfy { $0 <= 1.0 && $0 > 0.9 })
    }

    @Test(.timeLimit(.minutes(1)))
    func mutedStemsGiveSilence() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stems = try makeStems(in: dir, amplitude: 0.5).map { MixerExporter.StemInput(url: $0, gain: 0) }
        let output = dir.appendingPathComponent("mix.wav")

        try await MixerExporter.exportMix(stems: stems, to: output, pitchSemitones: 0, tempo: 1) { _ in }

        #expect(try TestAudio.channelPeaks(output).allSatisfy { $0 < 0.001 })
    }

    // Regression: ljudet gick genom tidsenheten även vid 100 % tempo och 0 halvtoner,
    // vilket mjukade upp ljudbilden. Nu ska en neutral export vara exakt summan av stems.
    @Test(.timeLimit(.minutes(1)))
    func neutralExportIsExactSumOfStems() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try makeStems(in: dir, amplitude: 0.3)
        let output = dir.appendingPathComponent("mix.wav")

        try await MixerExporter.exportMix(
            stems: urls.map { MixerExporter.StemInput(url: $0, gain: 1) },
            to: output, pitchSemitones: 0, tempo: 1
        ) { _ in }

        let mix = try samples(of: output)
        let parts = try urls.map(samples(of:))
        #expect(mix.count == parts[0].count)
        for i in stride(from: 0, to: mix.count, by: 101) {
            #expect(abs(mix[i] - (parts[0][i] + parts[1][i])) < 1e-4)
        }
    }

    private func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
