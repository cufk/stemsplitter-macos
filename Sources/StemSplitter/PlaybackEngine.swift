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
///   spelare (en per stem, volym) → stem-mixer → tonhöjd/tempo (en gemensam) → huvudmixer.
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

    let playhead = Playhead()

    private let engine = AVAudioEngine()
    private let stemMixer = AVAudioMixerNode()
    private let timePitch = AVAudioUnitTimePitch()
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
        var busSampleRate: Double = 0
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
            if busSampleRate == 0 { busSampleRate = file.processingFormat.sampleRate }
        }
        let busFormat = AVAudioFormat(standardFormatWithSampleRate: busSampleRate > 0 ? busSampleRate : 44100, channels: 2)
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
        pendingCompletions = scheduled
        startOffset = start
        playhead.position = start

        // Alla spelare startar på samma host-tid → samplesynkrona stems.
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05))
        for player in players.values {
            player.play(at: startTime)
        }
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
