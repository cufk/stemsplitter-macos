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
    @Published var showPythonInstallPrompt = false

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
        inputURL = input
        stems = []

        guard await ensurePythonOrPrompt() else { return }

        // Cache: samma fil (path+storlek+datum) med alla fyra stems -> ladda direkt
        let key = cacheKey(for: input)
        let projectDir = SeparationService.appSupportRoot
            .appendingPathComponent("projects/\(key)", isDirectory: true)
        let cachedURLs = StemKind.allCases.compactMap { kind -> URL? in
            let url = projectDir.appendingPathComponent("\(kind.rawValue).wav")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if cachedURLs.count == StemKind.allCases.count {
            let tracks = StemKind.allCases.map { StemTrack(kind: $0, url: projectDir.appendingPathComponent("\($0.rawValue).wav")) }
            await finishLoad(tracks: tracks, input: input, cached: true)
            return
        }

        phase = .busy
        statusMessage = "Förbereder lokal AI-miljö (första körningen kan ta några minuter)…"
        progressFraction = nil
        do {
            let located = try await separator.separate(input: input) { message, fraction in
                Task { @MainActor in
                    self.statusMessage = message
                    if let fraction { self.progressFraction = fraction }
                }
            }
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
            await finishLoad(tracks: tracks, input: input, cached: false)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func ensurePythonOrPrompt() async -> Bool {
        if await PythonLocator.find() != nil {
            return true
        }
        await MainActor.run {
            showPythonInstallPrompt = true
        }
        return false
    }

    func installPython() {
        showPythonInstallPrompt = false
        Task {
            await MainActor.run {
                phase = .busy
                statusMessage = "Laddar ner Python 3.12 från python.org…"
                progressFraction = 0
            }
            do {
                let pkg = try await PythonInstaller.download { fraction in
                    Task { @MainActor in
                        self.progressFraction = fraction
                        self.statusMessage = "Laddar ner Python 3.12… \(Int(fraction * 100)) %"
                    }
                }
                PythonInstaller.openInstaller(at: pkg)
                await MainActor.run {
                    phase = .idle
                    statusMessage = "Installera paketet i Installer (ange lösenord), starta sedan om StemSplitter."
                }
            } catch {
                await MainActor.run {
                    phase = .failed("Kunde inte ladda ner Python: \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishLoad(tracks: [StemTrack], input: URL, cached: Bool) async {
        do {
            try playback.load(tracks)
            stems = tracks
            await computeWaveforms(for: tracks)
            phase = .ready
            statusMessage = cached ? "Klart (cachad): \(input.lastPathComponent)" : "Klart: \(input.lastPathComponent)"
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return fnv1a("\(url.path)|\(size)|\(modified)")
    }

    private func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
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
