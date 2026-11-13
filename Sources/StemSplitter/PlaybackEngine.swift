import AVFoundation
import Combine
import StemSplitterCore

final class PlaybackEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var isLooping = false
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var players: [StemKind: AVAudioPlayerNode] = [:]
    private var files: [StemKind: AVAudioFile] = [:]
    private var tracks: [StemTrack] = []
    private var startHostTime: UInt64 = 0
    private var startOffset: TimeInterval = 0
    private var pendingCompletions = 0
    private var timer: Timer?

    func load(_ newTracks: [StemTrack]) throws {
        unload()
        tracks = newTracks
        var maxDuration: TimeInterval = 0
        for track in newTracks {
            let file = try AVAudioFile(forReading: track.url)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            player.volume = track.muted ? 0 : Float(track.volume)
            files[track.kind] = file
            players[track.kind] = player
            maxDuration = max(maxDuration, Double(file.length) / file.processingFormat.sampleRate)
        }
        duration = maxDuration
        position = 0
    }

    func unload() {
        stop()
        for (_, player) in players {
            engine.detach(player)
        }
        players.removeAll()
        files.removeAll()
        tracks.removeAll()
        duration = 0
        position = 0
    }

    func setVolume(_ kind: StemKind, volume: Double, muted: Bool) {
        players[kind]?.volume = muted ? 0 : Float(volume)
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
        // Bygg om hela ljudgrafen från början — undviker stale-läge efter stop/paus
        for (_, player) in players {
            player.stop()
            engine.detach(player)
        }
        players.removeAll()
        files.removeAll()
        if engine.isRunning {
            engine.stop()
        }
        do {
            for track in tracks {
                let file = try AVAudioFile(forReading: track.url)
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
                player.volume = track.muted ? 0 : Float(track.volume)
                files[track.kind] = file
                players[track.kind] = player
            }
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
            print("[PlaybackEngine] spelar upp \(tracks.count) stems från \(offset)s, duration=\(duration)")
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
        position = min(startOffset + elapsed, duration)
    }
}
