import AppKit
import Combine
import Foundation
import StemSplitterCore
import UniformTypeIdentifiers

enum Phase: Equatable {
    case idle
    case busy
    case ready
    case failed(String)
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var statusMessage = ""
    @Published var progressFraction: Double?
    @Published var stems: [StemTrack] = []
    @Published var inputURL: URL?
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportedURL: URL?

    let playback = PlaybackEngine()
    private let separator = SeparationService()

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Välj en lokal ljudfil du har rätt att använda"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { await self?.load(url) }
        }
    }

    func load(_ input: URL) async {
        guard AudioFileSupport.isSupported(input) else {
            phase = .failed("Filformatet stöds inte: .\(input.pathExtension)")
            return
        }
        phase = .busy
        statusMessage = "Förbereder lokal AI-miljö (första körningen kan ta några minuter)…"
        progressFraction = nil
        stems = []
        inputURL = input
        do {
            let located = try await separator.separate(input: input) { message, fraction in
                Task { @MainActor in
                    self.statusMessage = message
                    if let fraction { self.progressFraction = fraction }
                }
            }
            let projectDir = SeparationService.appSupportRoot
                .appendingPathComponent("projects/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            var tracks: [StemTrack] = []
            for kind in StemKind.allCases {
                guard let url = located[kind] else { continue }
                let destination = projectDir.appendingPathComponent("\(kind.rawValue).wav")
                try FileManager.default.copyItem(at: url, to: destination)
                tracks.append(StemTrack(kind: kind, url: destination))
            }
            guard !tracks.isEmpty else {
                throw SeparationService.SeparationError.noStemsFound
            }
            try playback.load(tracks)
            stems = tracks
            await computeWaveforms(for: tracks)
            phase = .ready
            statusMessage = "Klart: \(input.lastPathComponent)"
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func computeWaveforms(for tracks: [StemTrack]) async {
        await withTaskGroup(of: (StemKind, [Float])?.self) { group in
            for track in tracks {
                group.addTask {
                    (track.kind, await WaveformComputer.peaks(for: track.url))
                }
            }
            var peaksByKind: [StemKind: [Float]] = [:]
            for await result in group {
                if let result { peaksByKind[result.0] = result.1 }
            }
            for track in tracks {
                track.waveform = peaksByKind[track.kind] ?? []
            }
        }
    }

    func setVolume(_ kind: StemKind, volume: Double, muted: Bool) {
        playback.setVolume(kind, volume: volume, muted: muted)
    }

    func exportMix() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = ((inputURL?.deletingPathExtension().lastPathComponent) ?? "mix") + "-mix.wav"
        panel.message = "Spara den mixade filen (med dina aktuella volyminställningar)"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { await self?.export(to: url) }
        }
    }

    func export(to url: URL) async {
        guard !stems.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        exportedURL = nil
        do {
            try await MixerExporter.exportMix(stems: stems, to: url) { progress in
                Task { @MainActor in self.exportProgress = progress }
            }
            exportedURL = url
        } catch {
            phase = .failed("Export misslyckades: \(error.localizedDescription)")
        }
        isExporting = false
    }
}
