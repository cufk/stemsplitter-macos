import AVFoundation
import StemSplitterCore

enum MixerExporter {
    private static let sampleRate: Double = 44100
    private static let channels: AVAudioChannelCount = 2
    private static let chunkFrames: AVAudioFrameCount = 4096

    /// Renderar en mix offline genom samma kedja som uppspelningen:
    /// spelare -> AVAudioUnitTimePitch (pitch/tempo) -> mixer, med per-stem volym/mute.
    static func exportMix(
        stems: [StemTrack],
        to outputURL: URL,
        pitchSemitones: Double,
        tempo: Double,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard !stems.isEmpty else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: false
        )

        let engine = AVAudioEngine()
        var players: [AVAudioPlayerNode] = []
        var totalDuration: TimeInterval = 0

        for stem in stems {
            let file = try AVAudioFile(forReading: stem.url)
            totalDuration = max(totalDuration, Double(file.length) / file.processingFormat.sampleRate)
            let player = AVAudioPlayerNode()
            let unit = AVAudioUnitTimePitch()
            unit.pitch = Float(pitchSemitones)
            unit.rate = Float(tempo)
            engine.attach(player)
            engine.attach(unit)
            engine.connect(player, to: unit, format: file.processingFormat)
            engine.connect(unit, to: engine.mainMixerNode, format: format)
            player.volume = stem.muted ? 0 : Float(stem.volume)
            try await player.scheduleFile(file, at: nil)
            players.append(player)
        }

        try await engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkFrames)
        try engine.start()
        for player in players {
            player.play()
        }

        let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        )!
        let expectedOutputFrames = AVAudioFramePosition(totalDuration * format.sampleRate / max(tempo, 0.01))

        while true {
            let status = try engine.renderOffline(buffer.frameCapacity, to: buffer)
            if status == .success {
                if buffer.frameLength > 0 {
                    try outputFile.write(from: buffer)
                }
                progress(Double(engine.manualRenderingSampleTime) / Double(max(1, expectedOutputFrames)))
            } else if status == .insufficientDataFromInputNode {
                break
            } else {
                engine.stop()
                throw ExportError.renderFailed
            }
            await Task.yield()
        }
        engine.stop()
        progress(1)
    }

    enum ExportError: LocalizedError {
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "Offline-renderingen misslyckades."
            }
        }
    }
}
