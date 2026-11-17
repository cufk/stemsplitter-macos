import AVFoundation
import Foundation
import Testing
@testable import StemSplitterAudio

struct AudioConverterTests {
    // Regression: konvertering av alla icke-WAV-filer föll med
    // "Foundation._GenericObjCError error 0" eftersom källfilen lästes förbi slutet.
    @Test func convertsAAC48kMonoToStereo44k() throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("mono-48k.m4a")
        try TestAudio.writeSine(to: input, sampleRate: 48000, channels: 1, seconds: 2, aac: true)

        let output = try AudioConverter.wavCopy(of: input, in: dir)

        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == 44100)
        #expect(file.fileFormat.channelCount == 2)
        // AAC har några tusen frames utfyllnad i början/slutet
        #expect(abs(Double(file.length) - 88200) < 4410)
        let peaks = try TestAudio.channelPeaks(output)
        #expect(peaks.count == 2)
        // Mono ska hamna i båda kanalerna, inte bara vänster
        #expect(peaks.allSatisfy { $0 > 0.3 && $0 < 0.7 })
    }

    @Test func convertsStereoWavWithSameLength() throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("stereo.aiff")
        try TestAudio.writeSine(to: input, sampleRate: 44100, channels: 2, seconds: 1)

        let output = try AudioConverter.wavCopy(of: input, in: dir)

        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == 44100)
        #expect(abs(file.length - 44100) <= 1)
    }

    @Test func missingFileGivesReadableError() throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: AudioConverter.ConversionError.self) {
            try AudioConverter.wavCopy(of: dir.appendingPathComponent("finns-inte.mp3"), in: dir)
        }
        // Inga halvfärdiga filer lämnas kvar
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}

struct AudioConverterProgressTests {
    @Test func reportsIncreasingProgressUpToOne() throws {
        let dir = try TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("lat.m4a")
        try TestAudio.writeSine(to: input, sampleRate: 48000, channels: 2, seconds: 3, aac: true)

        var values: [Double] = []
        _ = try AudioConverter.wavCopy(of: input, in: dir) { values.append($0) }

        #expect(values.count > 3)
        #expect(values == values.sorted())
        #expect(values.last == 1)
    }
}
