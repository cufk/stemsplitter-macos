import AVFoundation
import Combine
import StemSplitterCore

final class PlaybackEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var isLooping = false
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    /// Tonläge i halvtoner (-12...+12). Ändrar INTE tempo.
    @Published var pitchSemitones: Double = 0 {
        didSet { applyPitch() }
    }

    /// Tempo som multipel (0.5...2.0). Ändrar INTE tonläge.
    @Published var tempo: Double = 1.0 {
        didSet { applyTempo() }
    }

    private let engine = AVAudioEngine()
    private var players: [StemKind: AVAudioPlayerNode] = [:]
    private var timePitches: [StemKind: AVAudioUnitTimePitch] = [:]
    private var files: [StemKind: AVAudioFile] = [:]
    private var tracks: [StemTrack] = []
    private var startHostTime: UInt64 = 0
    private var startOffset: TimeInterval = 0
    private var pendingCompletions = 0
    private var timer: Timer?

    func load(_ newTracks: [StemTrack]) throws {
        unload()
        tracks = newTracks
        try buildGraph()
        duration = tracks.reduce(0) { max($0, files[$1.kind].map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0) }
        position = 0
    }

    /// Bygger (om) hela ljudgrafen: spelare -> AVAudioUnitTimePitch -> mixer.
    private func buildGraph() throws {
        for (_, player) in players {
            player.stop()
            engine.detach(player)
        }
        for (_, unit) in timePitches {
            engine.detach(unit)
        }
        players.removeAll()
        timePitches.removeAll()
        files.removeAll()
        if engine.isRunning {
            engine.stop()
        }
        for track in tracks {
            let file = try AVAudioFile(forReading: track.url)
            let player = AVAudioPlayerNode()
            let unit = AVAudioUnitTimePitch()
            unit.pitch = Float(pitchSemitones)
            unit.rate = Float(tempo)
            engine.attach(player)
            engine.attach(unit)
            engine.connect(player, to: unit, format: file.processingFormat)
            engine.connect(unit, to: engine.mainMixerNode, format: file.processingFormat)
            player.volume = track.muted ? 0 : Float(track.volume)
            files[track.kind] = file
            players[track.kind] = player
            timePitches[track.kind] = unit
        }
    }

    func unload() {
        stop()
        for (_, player) in players {
            engine.detach(player)
        }
        for (_, unit) in timePitches {
            engine.detach(unit)
        }
        players.removeAll()
        timePitches.removeAll()
        files.removeAll()
        tracks.removeAll()
        duration = 0
        position = 0
    }

    func setVolume(_ kind: StemKind, volume: Double, muted: Bool) {
        players[kind]?.volume = muted ? 0 : Float(volume)
    }

    private func applyPitch() {
        for (_, unit) in timePitches {
            unit.pitch = Float(pitchSemitones)
        }
    }

    private func applyTempo() {
        if isPlaying {
            updatePosition()
            startOffset = position
            startHostTime = mach_absolute_time()
        }
        for (_, unit) in timePitches {
            unit.rate = Float(tempo)
        }
    }

    func resetTuning() {
        pitchSemitones = 0
        tempo = 1.0
    }

    func togglePlay() {
        Task { @MainActor in
            if isPlaying {
                pause()
            } else {
                let from = position >= duration ? 0 : position
                await play(from: from)
            }
        }
    }

    func play(from offset: TimeInterval) async {
        guard !tracks.isEmpty else { return }
        await MainActor.run {
            isPlaying = false
            stopTimer()
        }
        do {
            try buildGraph()
            engine.prepare()
            try engine.start()
            pendingCompletions = tracks.count
            for track in tracks {
                guard let file = files[track.kind], let player = players[track.kind] else { continue }
                let fileRate = file.processingFormat.sampleRate
                let maxFrame: AVAudioFramePosition = file.length > 0 ? file.length - 1 : 0
                let startFrame = min(AVAudioFramePosition(offset * fileRate), maxFrame)
                file.framePosition = startFrame
                player.scheduleFile(file, at: nil) { [weak self] in
                    self?.handleCompletion()
                }
            }
            for track in tracks {
                players[track.kind]?.play()
            }
            startHostTime = mach_absolute_time()
            startOffset = offset
            print("[PlaybackEngine] spelar upp \(tracks.count) stems från \(offset)s, tempo=\(tempo), pitch=\(pitchSemitones)")
            await MainActor.run {
                isPlaying = true
                startTimer()
            }
        } catch {
            print("[PlaybackEngine] start misslyckades: \(error)")
            await MainActor.run {
                isPlaying = false
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        updatePosition()
        stopScheduling()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        stopScheduling()
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
        position = 0
        startOffset = 0
        stopTimer()
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(0, seconds), duration)
        if isPlaying {
            Task { await play(from: target) }
        } else {
            position = target
            startOffset = target
        }
    }

    private func stopScheduling() {
        for (_, player) in players {
            player.stop()
        }
    }

    private static func secondsToHostTime(_ seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64(seconds * 1e9 * Double(info.denom) / Double(info.numer))
    }

    private static func hostTimeToSeconds(_ hostTime: UInt64) -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(hostTime) * Double(info.numer) / Double(info.denom) / 1e9
    }

    private func handleCompletion() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingCompletions -= 1
            guard self.pendingCompletions <= 0 else { return }
            if self.isLooping {
                Task { await self.play(from: 0) }
            } else {
                self.isPlaying = false
                self.position = self.duration
                self.stopTimer()
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updatePosition() {
        guard isPlaying, startHostTime != 0 else { return }
        let now = mach_absolute_time()
        let elapsed = Self.hostTimeToSeconds(now) - Self.hostTimeToSeconds(startHostTime)
        position = min(startOffset + elapsed * tempo, duration)
    }
}
