import AVFoundation
import StemSplitterCore

public enum StemResidual {
    public enum ResidualError: LocalizedError {
        case formatMismatch

        public var errorDescription: String? {
            "Stems och originalet har olika format och kan inte jämföras."
        }
    }

    public struct Report: Sendable {
        /// Nivån på det som saknades i de separerade stems, relativt originalet (dB).
        public let missingLevel: Double
    }

    /// Skriver om `target` (normalt other.wav) som `mix − Σ subtract`, så att alla stems
    /// tillsammans blir exakt originalet. Allt som Demucs inte placerade någonstans hamnar då i "Övrigt".
    /// Filerna måste ha samma samplingsfrekvens och antal kanaler (mixen görs om till 44,1 kHz stereo först).
    @discardableResult
    public static func rebuild(target: URL, mix: URL, subtract: [URL]) throws -> Report {
        let mixFile = try AVAudioFile(forReading: mix)
        let oldTarget = try AVAudioFile(forReading: target)
        let stemFiles = try subtract.map { try AVAudioFile(forReading: $0) }
        let format = mixFile.processingFormat
        for file in stemFiles + [oldTarget] where
            file.processingFormat.sampleRate != format.sampleRate || file.processingFormat.channelCount != format.channelCount {
            throw ResidualError.formatMismatch
        }

        let chunk: AVAudioFrameCount = 65536
        guard let mixBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              let oldBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)
        else { throw ResidualError.formatMismatch }
        let stemBuffers = try stemFiles.map { _ -> AVAudioPCMBuffer in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw ResidualError.formatMismatch }
            return buffer
        }

        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).wav")
        var mixEnergy = 0.0
        var missingEnergy = 0.0
        do {
            let output = try AVAudioFile(forWriting: temporary, settings: format.fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let length = min(mixFile.length, stemFiles.map(\.length).min() ?? mixFile.length, oldTarget.length)
            var position: AVAudioFramePosition = 0
            while position < length {
                let frames = AVAudioFrameCount(min(Int64(chunk), length - position))
                try mixFile.read(into: mixBuffer, frameCount: frames)
                try oldTarget.read(into: oldBuffer, frameCount: frames)
                for (file, buffer) in zip(stemFiles, stemBuffers) {
                    try file.read(into: buffer, frameCount: frames)
                }
                let count = Int(min(mixBuffer.frameLength, oldBuffer.frameLength, stemBuffers.map(\.frameLength).min() ?? mixBuffer.frameLength))
                guard count > 0 else { break }
                for channel in 0..<Int(format.channelCount) {
                    let out = outBuffer.floatChannelData![channel]
                    let mixData = mixBuffer.floatChannelData![channel]
                    let old = oldBuffer.floatChannelData![channel]
                    MixMath.residual(
                        mix: mixData,
                        subtracting: stemBuffers.map { UnsafePointer($0.floatChannelData![channel]) },
                        into: out,
                        count: count
                    )
                    for i in 0..<count {
                        mixEnergy += Double(mixData[i] * mixData[i])
                        let missing = out[i] - old[i]
                        missingEnergy += Double(missing * missing)
                    }
                }
                outBuffer.frameLength = AVAudioFrameCount(count)
                try output.write(from: outBuffer)
                position += AVAudioFramePosition(count)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        return Report(missingLevel: MixMath.decibels(energy: missingEnergy, reference: mixEnergy))
    }
}
