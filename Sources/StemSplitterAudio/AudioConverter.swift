import AVFoundation

public enum AudioConverter {
    public enum ConversionError: LocalizedError {
        case unsupported
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupported: return "Kunde inte konvertera filen till WAV."
            case .failed(let reason): return "Konverteringen till WAV misslyckades: \(reason)"
            }
        }
    }

    /// Konverterar en ljudfil till en temporär 44,1 kHz stereo float32-WAV
    /// (demucs/torchaudio kan inte alltid läsa t.ex. MP3 utan ffmpeg).
    /// Hanterar andra samplingsfrekvenser (t.ex. 48 kHz) och mono. Anroparen äger och tar bort filen.
    public static func wavCopy(of input: URL, in directory: URL, progress: ((Double) -> Void)? = nil) throws -> URL {
        let source: AVAudioFile
        do {
            source = try AVAudioFile(forReading: input)
        } catch {
            throw ConversionError.failed("kunde inte öppna \(input.lastPathComponent) (\(error.localizedDescription))")
        }
        let sourceFormat = source.processingFormat
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: format),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 8192)
        else {
            throw ConversionError.unsupported
        }
        if sourceFormat.channelCount == 1 {
            // Mono till båda kanalerna, inte bara vänster
            converter.channelMap = [0, 0]
        }

        let destination = directory.appendingPathComponent("input-\(UUID().uuidString).wav")
        do {
            let destinationFile = try AVAudioFile(
                forWriting: destination,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: false
            )
            var reachedEnd = false
            var readError: Error?

            while true {
                try Task.checkCancellation()
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
                    throw ConversionError.unsupported
                }
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { packetCount, inputStatus in
                    // Läs aldrig förbi filslut: AVAudioFile.read misslyckas då utan NSError
                    // (visades som "Foundation._GenericObjCError error 0").
                    if reachedEnd || source.framePosition >= source.length {
                        reachedEnd = true
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    do {
                        try source.read(into: inputBuffer, frameCount: min(packetCount, inputBuffer.frameCapacity))
                    } catch {
                        readError = error
                        reachedEnd = true
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    if inputBuffer.frameLength == 0 {
                        reachedEnd = true
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputStatus.pointee = .haveData
                    return inputBuffer
                }
                if let readError { throw readError }
                if status == .error {
                    throw ConversionError.failed(conversionError?.localizedDescription ?? "okänt fel")
                }
                if outputBuffer.frameLength > 0 {
                    try destinationFile.write(from: outputBuffer)
                }
                if let progress, source.length > 0 {
                    progress(min(1, Double(source.framePosition) / Double(source.length)))
                }
                if status == .endOfStream || (status == .inputRanDry && reachedEnd) {
                    break
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }
}
