import Foundation
import Testing
@testable import StemSplitterAudio

struct WaveformComputerTests {
    @Test func peaksFollowAmplitude() async throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sine.wav")
        try TestAudio.writeSine(to: url, sampleRate: 44100, channels: 2, seconds: 1, amplitude: 0.5)

        let peaks = await WaveformComputer.peaks(for: url, bucketCount: 50)

        #expect(peaks.count == 50)
        #expect(peaks.allSatisfy { $0 > 0.45 && $0 <= 0.5001 })
    }

    @Test func missingFileGivesNoPeaks() async {
        #expect(await WaveformComputer.peaks(for: URL(fileURLWithPath: "/finns/inte.wav")).isEmpty)
    }
}
