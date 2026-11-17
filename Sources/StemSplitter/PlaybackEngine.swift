import AVFoundation
import Combine
import StemSplitterCore

/// Uppspelningspositionen i ett eget objekt, så att bara vyer som visar positionen
/// ritas om ~30 gånger per sekund (inte hela fönstret).
@MainActor
final class Playhead: ObservableObject {
    @Published var position: TimeInterval = 0
}

/// Ljudgraf som byggs en gång per låt:
///   spelare (en per stem, volym) + klickspelare → stem-mixer → tonhöjd/tempo (en gemensam) → huvudmixer.
/// Klicket ligger före tempo-enheten och följer därför låten även när tempot ändras.
/// Play/paus/sök startar bara om spelarna — motorn och filerna ligger kvar.
@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var isLooping = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: String?

    /// Tonläge i halvtoner (-12...+12). Ändrar inte tempo.
    @Published var pitchSemitones: Double = 0 {
        didSet { timePitch.pitch = MixMath.cents(fromSemitones: pitchSemitones) }
    }

    /// Tempo som multipel (0.5...2.0). Ändrar inte tonläge.
    @Published var tempo: Double = 1.0 {
        didSet { timePitch.rate = Float(tempo) }
    }

    /// Tempo och slag för klicket och taktlinjalen.
    @Published var beatGrid: BeatGrid? {
        didSet { rescheduleIfPlaying() }
    }

    @Published var clickEnabled = false {
        didSet { updateClickVolume() }
    }

    @Published var clickVolume: Double = 0.7 {
        didSet { updateClickVolume() }
    }

    let playhead = Playhead()

    private let engine = AVAudioEngine()
    private let stemMixer = AVAudioMixerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let clickPlayer = AVAudioPlayerNode()
    private var clickBuffers: (accent: AVAudioPCMBuffer, normal: AVAudioPCMBuffer)?
    private var busSampleRate: Double = 44100
    private var players: [StemKind: AVAudioPlayerNode] = [:]
    private var files: [StemKind: AVAudioFile] = [:]
    private var referenceKind: StemKind?
    /// Ökas varje gång spelarna stoppas, så att gamla klar-signaler (som även kommer vid stop) ignoreras.
    private var generation = 0
    private var pendingCompletions = 0
    private var startOffset: TimeInterval = 0
    private var timer: Timer?
    private var configurationObserver: NSObjectProtocol?

    init() {
        engine.attach(stemMixer)
        engine.attach(timePitch)
        engine.attach(clickPlayer)
        updateClickVolume()
        // T.ex. byte till AirPods: motorn stoppas av systemet — fortsätt där vi var.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }
    }

    var isLoaded: Bool { !players.isEmpty }

    func load(_ tracks: [StemTrack]) throws {
        unload()
        var firstSampleRate: Double = 0
        var longest: (kind: StemKind, length: Double)?
        for track in tracks {
            let file = try AVAudioFile(forReading: track.url)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: stemMixer, fromBus: 0, toBus: stemMixer.nextAvailableInputBus, format: file.processingFormat)
            players[track.kind] = player
            files[track.kind] = file
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            if seconds > (longest?.length ?? -1) { longest = (track.kind, seconds) }
            if firstSampleRate == 0 { firstSampleRate = file.processingFormat.sampleRate }
        }
        busSampleRate = firstSampleRate > 0 ? firstSampleRate : 44100
        let busFormat = AVAudioFormat(standardFormatWithSampleRate: busSampleRate, channels: 2)
        connectClick()
        engine.connect(stemMixer, to: timePitch, format: busFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: busFormat)
        timePitch.pitch = MixMath.cents(fromSemitones: pitchSemitones)
        timePitch.rate = Float(tempo)
        referenceKind = longest?.kind
        duration = longest?.length ?? 0
        playhead.position = 0
        startOffset = 0
        engine.prepare()
    }

    func unload() {
        stopPlayers()
        stopTimer()
        isPlaying = false
        for player in players.values {
            engine.detach(player)
        }
        players.removeAll()
        files.removeAll()
        referenceKind = nil
        beatGrid = nil
        if engine.isRunning { engine.stop() }
        duration = 0
        playhead.position = 0
    }

    func setGain(_ kind: StemKind, _ gain: Float) {
        players[kind]?.volume = gain
    }

    func resetTuning() {
        pitchSemitones = 0
        tempo = 1.0
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play(from offset: TimeInterval? = nil) {
        guard isLoaded else { return }
        let start = Transport.resumePosition(offset ?? playhead.position, duration: duration)
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            lastError = "Kunde inte starta ljudet: \(error.localizedDescription)"
            return
        }

        stopPlayers()
        let currentGeneration = generation
        var scheduled = 0
        for (kind, player) in players {
            guard let file = files[kind],
                  let segment = Transport.segment(offset: start, sampleRate: file.processingFormat.sampleRate, length: file.length)
            else { continue }
            scheduled += 1
            player.scheduleSegment(
                file,
                startingFrame: segment.start,
                frameCount: AVAudioFrameCount(clamping: segment.count),
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.segmentFinished(generation: currentGeneration)
                }
            }
        }
        guard scheduled > 0 else { return }
        scheduleClicks(from: start)
        pendingCompletions = scheduled
        startOffset = start
        playhead.position = start

        // Alla spelare startar på samma host-tid → samplesynkrona stems.
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05))
        for player in players.values {
            player.play(at: startTime)
        }
        clickPlayer.play(at: startTime)
        isPlaying = true
        lastError = nil
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        updatePosition()
        stopPlayers()
        isPlaying = false
        stopTimer()
        engine.pause()
    }

    func stop() {
        stopPlayers()
        isPlaying = false
        stopTimer()
        playhead.position = 0
        startOffset = 0
        if engine.isRunning { engine.pause() }
    }

    func seek(to seconds: TimeInterval) {
        let target = Transport.clamp(seconds, duration: duration)
        if isPlaying {
            play(from: target)
        } else {
            playhead.position = target
            startOffset = target
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: Transport.skip(from: playhead.position, by: seconds, duration: duration))
    }

    private func stopPlayers() {
        generation &+= 1
        for player in players.values {
            player.stop()
        }
        clickPlayer.stop()
    }

    // MARK: - Klick

    private func connectClick() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: busSampleRate, channels: 1) else { return }
        engine.disconnectNodeOutput(clickPlayer)
        engine.connect(clickPlayer, to: stemMixer, fromBus: 0, toBus: stemMixer.nextAvailableInputBus, format: format)
        func buffer(accent: Bool) -> AVAudioPCMBuffer? {
            let samples = ClickSynth.click(sampleRate: busSampleRate, accent: accent)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (index, value) in samples.enumerated() { channel[index] = value }
            return buffer
        }
        if let accent = buffer(accent: true), let normal = buffer(accent: false) {
            clickBuffers = (accent, normal)
        }
    }

    /// Schemalägger ett klick per slag från `start`, i spelarens egen tidslinje (källans tid).
    private func scheduleClicks(from start: TimeInterval) {
        guard let grid = beatGrid, let buffers = clickBuffers else { return }
        let sampleRate = busSampleRate
        for index in grid.firstBeatIndex(atOrAfter: start - 0.001)..<grid.beats.count {
            let frame = AVAudioFramePosition(max(0, (grid.beats[index] - start) * sampleRate).rounded())
            clickPlayer.scheduleBuffer(
                grid.isDownbeat(index) ? buffers.accent : buffers.normal,
                at: AVAudioTime(sampleTime: frame, atRate: sampleRate),
                options: [],
                completionHandler: nil
            )
        }
    }

    private func updateClickVolume() {
        clickPlayer.volume = clickEnabled ? Float(clickVolume) : 0
    }

    private func rescheduleIfPlaying() {
        guard isPlaying else { return }
        updatePosition()
        play(from: playhead.position)
    }

    private func segmentFinished(generation finished: Int) {
        guard finished == generation, isPlaying else { return }
        pendingCompletions -= 1
        guard pendingCompletions <= 0 else { return }
        if isLooping {
            play(from: 0)
        } else {
            stopPlayers()
            isPlaying = false
            stopTimer()
            playhead.position = duration
            engine.pause()
        }
    }

    private func handleConfigurationChange() {
        guard isPlaying else { return }
        updatePosition()
        isPlaying = false
        play(from: playhead.position)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Positionen räknas från referensspelarens renderade frames (källans tid),
    /// så den stämmer även när tempot ändras under uppspelning.
    private func updatePosition() {
        guard isPlaying,
              let kind = referenceKind,
              let player = players[kind],
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return }
        playhead.position = Transport.position(
            startOffset: startOffset,
            renderedFrames: playerTime.sampleTime,
            sampleRate: playerTime.sampleRate,
            duration: duration
        )
    }
}
