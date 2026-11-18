import AVFoundation
import Foundation
@testable import StemSplitterAudio

/// Hjälpfunktioner som skapar riktiga ljudfiler för testerna.
enum TestAudio {
    static func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stemsplitter-audiotest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Skriver en sinuston. Med `aac: true` blir det en komprimerad AAC-fil (som M4A från t.ex. Musik-appen).
    static func writeSine(
        to url: URL,
        sampleRate: Double,
        channels: AVAudioChannelCount,
        seconds: Double,
        amplitude: Float = 0.5,
        frequency: Double = 440,
        aac: Bool = false
    ) throws {
        let processing = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let settings: [String: Any]
        if aac {
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 64000
            ]
        } else {
            settings = processing.fileSettings
        }
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                data[i] = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
            }
        }
        // Filen stängs (och AAC-filen slutförs) när `file` släpps i slutet av scopet.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    /// Högsta |sample| per kanal i hela filen.
    static func channelPeaks(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        return (0..<Int(buffer.format.channelCount)).map { channel in
            let data = buffer.floatChannelData![channel]
            var peak: Float = 0
            for i in 0..<count { peak = max(peak, abs(data[i])) }
            return peak
        }
    }
}
