import AVFoundation
import StemSplitterCore

public enum MixerExporter {
    public struct StemInput: Sendable {
        public let url: URL
        public let gain: Float

        public init(url: URL, gain: Float) {
            self.url = url
            self.gain = gain
        }
    }

    public enum ExportError: LocalizedError {
        case renderFailed

        public var errorDescription: String? {
            "Offline-renderingen misslyckades."
        }
    }

    private static let chunkFrames: AVAudioFrameCount = 8192

    /// Synkron hjälpfunktion: i en async-kontext föreslår kompilatorn async-varianten av
    /// scheduleFile, men den väntar tills filen spelats klart och skulle låsa exporten.
    private static func schedule(_ file: AVAudioFile, on player: AVAudioPlayerNode) {
        player.scheduleFile(file, at: nil, completionHandler: nil)
    }

    /// Renderar mixen offline genom samma kedja som uppspelningen:
    /// spelare (volym) → stem-mixer → tonhöjd/tempo → utdata. Klipps till [-1, 1].
    /// Tar bort den halvfärdiga filen om exporten avbryts eller misslyckas.
    public static func exportMix(
        stems: [StemInput],
        to outputURL: URL,
        pitchSemitones: Double,
        tempo: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard !stems.isEmpty else { return }

        let engine = AVAudioEngine()
        let stemMixer = AVAudioMixerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attach(stemMixer)
        engine.attach(timePitch)

        var sources: [(file: AVAudioFile, player: AVAudioPlayerNode)] = []
        var sourceDuration: Double = 0
        var sampleRate: Double = 0
        for stem in stems {
            let file = try AVAudioFile(forReading: stem.url)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: stemMixer, fromBus: 0, toBus: stemMixer.nextAvailableInputBus, format: file.processingFormat)
            player.volume = stem.gain
            sources.append((file, player))
            sourceDuration = max(sourceDuration, Double(file.length) / file.processingFormat.sampleRate)
            if sampleRate == 0 { sampleRate = file.processingFormat.sampleRate }
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw ExportError.renderFailed
        }
        engine.connect(stemMixer, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        timePitch.pitch = MixMath.cents(fromSemitones: pitchSemitones)
        timePitch.rate = Float(tempo)
        // Obearbetat ljud när tempo och tonläge är neutrala
        timePitch.bypass = MixMath.isNeutralTuning(tempo: tempo, semitones: pitchSemitones)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkFrames)
        for source in sources {
            schedule(source.file, on: source.player)
        }
        try engine.start()
        defer { engine.stop() }
        for source in sources {
            source.player.play()
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw ExportError.renderFailed
        }
        // Spelarna ger tystnad efter filslut i offline-läge, så vi måste själva veta när vi är klara.
        let total = MixMath.outputFrameCount(sourceDuration: sourceDuration, tempo: tempo, sampleRate: format.sampleRate)
            + (timePitch.bypass ? 0 : Int64(timePitch.latency * format.sampleRate))

        do {
            let output = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            var rendered: Int64 = 0
            render: while rendered < total {
                try Task.checkCancellation()
                let frames = AVAudioFrameCount(min(Int64(buffer.frameCapacity), total - rendered))
                let status = try engine.renderOffline(frames, to: buffer)
                switch status {
                case .success:
                    let count = Int(buffer.frameLength)
                    if count == 0 { break render }
                    if let channels = buffer.floatChannelData {
                        for channel in 0..<Int(buffer.format.channelCount) {
                            MixMath.clampChannel(channels[channel], count: count)
                        }
                    }
                    try output.write(from: buffer)
                    rendered += Int64(count)
                    progress(min(1, Double(rendered) / Double(max(1, total))))
                case .insufficientDataFromInputNode:
                    break render
                case .cannotDoInCurrentContext:
                    break
                case .error:
                    throw ExportError.renderFailed
                @unknown default:
                    throw ExportError.renderFailed
                }
                await Task.yield()
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        progress(1)
    }
}
