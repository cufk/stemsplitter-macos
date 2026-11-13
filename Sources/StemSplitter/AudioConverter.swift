import AVFoundation

enum AudioConverter {
    enum ConversionError: LocalizedError {
        case noAudioTrack
        case unsupported

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "Filen innehåller inget ljudspår."
            case .unsupported: return "Kunde inte konvertera filen till WAV."
            }
        }
    }

    /// Kopierar en ljudfil till en temporär 44,1 kHz stereo float32-WAV (demucs/torchaudio kan inte alltid läsa t.ex. MP3 utan ffmpeg).
    static func wavCopy(of input: URL) throws -> URL {
        let source = try AVAudioFile(forReading: input)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        )!
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        let destinationFile = try AVAudioFile(
            forWriting: destination,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: false
        )
        guard let converter = AVAudioConverter(from: source.processingFormat, to: format) else {
            throw ConversionError.unsupported
        }
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096)!
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!

        while source.framePosition < source.length {
            try source.read(into: inputBuffer, frameCount: 4096)
            let read = inputBuffer.frameLength
            if read == 0 { break }
            converter.convert(to: outputBuffer, from: inputBuffer)
            if outputBuffer.frameLength > 0 {
                try destinationFile.write(from: outputBuffer)
            }
        }
        return destination
    }
}
