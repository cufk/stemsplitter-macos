import AVFoundation
import StemSplitterCore

enum MixerExporter {
    private static let sampleRate: Double = 44100
    private static let channels: AVAudioChannelCount = 2
    private static let chunkFrames: AVAudioFrameCount = 44100

    static func exportMix(stems: [StemTrack], to outputURL: URL, progress: @escaping (Double) -> Void) async throws {
        guard !stems.isEmpty else { return }

        let commonFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: commonFormat.settings,
            commonFormat: commonFormat,
            interleaved: false
        )

        struct StemReader {
            let file: AVAudioFile
            let converter: AVAudioConverter
            let inputBuffer: AVAudioPCMBuffer
            let gain: Float
        }

        var readers: [StemReader] = []
        var totalFrames: AVAudioFramePosition = 0
        for stem in stems {
            let file = try AVAudioFile(forReading: stem.url)
            guard let converter = AVAudioConverter(from: file.processingFormat, to: commonFormat) else {
                throw ExportError.conversionFailed(stem.kind.rawValue)
            }
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames)!
            let duration = Double(file.length) / file.processingFormat.sampleRate
            totalFrames = max(totalFrames, AVAudioFramePosition(duration * sampleRate))
            readers.append(StemReader(
                file: file,
                converter: converter,
                inputBuffer: inputBuffer,
                gain: stem.muted ? 0 : Float(stem.volume)
            ))
        }

        let mixBuffer = AVAudioPCMBuffer(pcmFormat: commonFormat, frameCapacity: chunkFrames)!
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: commonFormat, frameCapacity: chunkFrames)!
        var written: AVAudioFramePosition = 0

        while written < totalFrames {
            let wanted = min(chunkFrames, totalFrames - written)
            mixBuffer.frameLength = wanted
            if let channelData = mixBuffer.floatChannelData {
                for channel in 0..<Int(channels) {
                    MixMath.zero(channelData[channel], count: Int(wanted))
                }
            }

            for reader in readers {
                let read = try reader.file.read(into: reader.inputBuffer, frameCount: wanted)
                guard read > 0 else { continue }
                _ = reader.converter.convert(to: convertedBuffer, from: reader.inputBuffer)
                let frames = min(convertedBuffer.frameLength, wanted)
                guard frames > 0, let converted = convertedBuffer.floatChannelData else { continue }
                if let mix = mixBuffer.floatChannelData {
                    for channel in 0..<Int(channels) {
                        let src = converted[channel]
                        let dst = mix[channel]
                        if reader.gain == 1 {
                            MixMath.accumulate(src, dst, count: Int(frames))
                        } else {
                            var temp = [Float](repeating: 0, count: Int(frames))
                            temp.withUnsafeMutableBufferPointer { tempPtr in
                                MixMath.applyGain(src, tempPtr.baseAddress!, count: Int(frames), gain: reader.gain)
                                MixMath.accumulate(tempPtr.baseAddress!, dst, count: Int(frames))
                            }
                        }
                    }
                }
            }

            if let channelData = mixBuffer.floatChannelData {
                for channel in 0..<Int(channels) {
                    MixMath.clampChannel(channelData[channel], count: Int(wanted))
                }
            }

            try outputFile.write(from: mixBuffer)
            written += wanted
            progress(Double(written) / Double(totalFrames))
            await Task.yield()
        }
    }

    enum ExportError: LocalizedError {
        case conversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .conversionFailed(let name):
                return "Kunde inte konvertera stem-filen \(name) till ett gemensamt format."
            }
        }
    }
}
