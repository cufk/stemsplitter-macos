import AppKit
import Combine
import Foundation
import StemSplitterAudio
import StemSplitterCore
import UniformTypeIdentifiers

enum Phase: Equatable {
    case idle
    case working
    case ready
    case failed(String)
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusMessage = ""
    @Published private(set) var progressFraction: Double?
    @Published private(set) var stems: [StemTrack] = []
    /// Om någon stem är solo — då dimmas övriga i gränssnittet.
    @Published private(set) var anySoloed = false
    @Published private(set) var title: String?
    @Published private(set) var currentProjectKey: String?
    @Published private(set) var library: [ProjectSummary] = []
    @Published private(set) var cacheSize: Int64 = 0
    @Published private(set) var isAnalyzingTempo = false
    @Published private(set) var isExporting = false
    @Published private(set) var exportProgress: Double = 0
    @Published var exportedURL: URL?
    @Published var alertMessage: String?
    @Published var showPythonInstallPrompt = false

    let playback = PlaybackEngine()
    private let separator = SeparationService()
    private var loadTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    /// Ökas för varje ny laddning; resultat från en äldre (avbruten) laddning ignoreras.
    private var loadID = 0
    private var lastInputURL: URL?
    private var trackObservers: Set<AnyCancellable> = []

    init() {
        SeparationService.removeStaleWorkDirectories()
        ProjectStore.removeStaleStaging()
        refreshLibrary()
    }

    var isReady: Bool { phase == .ready }

    // MARK: - Öppna

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Välj en lokal ljudfil du har rätt att använda"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.open(url) }
        }
    }

    func open(_ url: URL) {
        startLoad { id in await self.load(url, id: id) }
    }

    func selectProject(_ key: String) {
        guard key != currentProjectKey || phase != .ready else { return }
        startLoad { id in await self.openProject(key: key, id: id) }
    }

    func retry() {
        if let lastInputURL {
            open(lastInputURL)
        } else if let currentProjectKey {
            startLoad { id in await self.openProject(key: currentProjectKey, id: id) }
        }
    }

    func cancelWork() {
        loadTask?.cancel()
        loadTask = nil
        loadID += 1
        progressFraction = nil
        if stems.isEmpty {
            phase = .idle
            statusMessage = ""
        } else {
            phase = .ready
        }
    }

    private func startLoad(_ operation: @escaping @MainActor (Int) async -> Void) {
        loadTask?.cancel()
        loadID += 1
        let id = loadID
        loadTask = Task { await operation(id) }
    }

    private func isCurrent(_ id: Int) -> Bool {
        id == loadID && !Task.isCancelled
    }

    private func load(_ input: URL, id: Int) async {
        guard AudioFileSupport.isSupported(input) else {
            phase = .failed("Filformatet stöds inte: .\(input.pathExtension)")
            return
        }
        lastInputURL = input
        resetPlayer()
        title = input.deletingPathExtension().lastPathComponent
        phase = .working
        statusMessage = "Läser filen…"
        progressFraction = nil

        let key: String
        do {
            key = try await Task.detached(priority: .userInitiated) {
                try CacheKey.fingerprint(of: input)
            }.value
        } catch {
            if isCurrent(id) { phase = .failed("Kunde inte läsa filen: \(error.localizedDescription)") }
            return
        }
        guard isCurrent(id) else { return }

        if ProjectStore.stemURLs(key: key) != nil {
            await openProject(key: key, id: id)
            return
        }

        guard await PythonLocator.find() != nil else {
            guard isCurrent(id) else { return }
            phase = .idle
            showPythonInstallPrompt = true
            return
        }
        guard isCurrent(id) else { return }
        statusMessage = "Förbereder lokal AI-miljö…"

        do {
            let result = try await separator.separate(input: input) { [weak self] message, fraction in
                Task { @MainActor in
                    guard let self, self.isCurrent(id) else { return }
                    self.statusMessage = message
                    if let fraction { self.progressFraction = fraction }
                }
            }
            defer { try? FileManager.default.removeItem(at: result.workDirectory) }
            guard isCurrent(id) else { return }
            try ProjectStore.save(key: key, sourceName: input.lastPathComponent, model: result.model, stems: result.stems)
            refreshLibrary()
            await openProject(key: key, id: id)
        } catch {
            guard isCurrent(id), !(error is CancellationError) else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func openProject(key: String, id: Int) async {
        guard let urls = ProjectStore.stemURLs(key: key) else {
            refreshLibrary()
            phase = .failed(ProjectStore.StoreError.incomplete.localizedDescription)
            return
        }
        let meta = ProjectStore.meta(key: key)
        resetPlayer()
        let tracks = StemKind.allCases.compactMap { kind in urls[kind].map { StemTrack(kind: kind, url: $0) } }
        do {
            try playback.load(tracks)
        } catch {
            phase = .failed("Kunde inte öppna stems: \(error.localizedDescription)")
            return
        }
        stems = tracks
        observeTracks()
        currentProjectKey = key
        title = meta?.displayName ?? title ?? "Okänd låt"
        statusMessage = ""
        progressFraction = nil
        phase = .ready

        // Vågformer och tempo från cachen, annars beräknas och sparas de (parallellt).
        let cachedPeaks = meta.flatMap { meta in
            tracks.allSatisfy({ meta.peaks(for: $0.kind) != nil }) ? meta : nil
        }
        if let cachedPeaks {
            for track in tracks { track.waveform = cachedPeaks.peaks(for: track.kind) ?? [] }
        }
        if let grid = meta?.beatGrid {
            playback.beatGrid = grid
        }

        let needsGrid = meta?.beatGrid == nil
        if needsGrid { isAnalyzingTempo = true }
        // Tempoanalysen körs utanför huvudtråden medan vågformerna beräknas.
        let gridTask: Task<BeatGrid??, Never>? = needsGrid
            ? Task.detached(priority: .userInitiated) { await Self.analyzeTempo(urls: urls) }
            : nil

        if cachedPeaks == nil {
            let peaks = await computeWaveforms(for: tracks)
            if isCurrent(id), currentProjectKey == key {
                for track in tracks { track.waveform = peaks[track.kind] ?? [] }
                ProjectStore.savePeaks(key: key, peaks: peaks)
            }
        }
        guard let gridTask else { return }
        let analyzed = await withTaskCancellationHandler {
            await gridTask.value
        } onCancel: {
            gridTask.cancel()
        }
        guard isCurrent(id), currentProjectKey == key else { return }
        isAnalyzingTempo = false
        if let analyzed {
            playback.beatGrid = analyzed
            ProjectStore.saveBeatGrid(key: key, grid: analyzed)
        }
    }

    /// Tempo från trumspåret (tydligast puls), annars från "övrigt".
    /// Returnerar .some(nil) när analysen är klar men inget tempo hittades.
    private nonisolated static func analyzeTempo(urls: [StemKind: URL]) async -> BeatGrid?? {
        for kind in [StemKind.drums, .other, .bass] {
            guard let url = urls[kind] else { continue }
            if let grid = await BeatAnalyzer.analyze(url: url) {
                return .some(grid)
            }
            if Task.isCancelled { return nil }
        }
        return .some(nil)
    }

    // MARK: - Tempo

    func halveTempo() { updateGrid { $0.halved() } }
    func doubleTempo() { updateGrid { $0.doubled() } }
    func shiftDownbeat() { updateGrid { $0.shiftingDownbeat(by: 1) } }

    func reanalyzeTempo() {
        guard let key = currentProjectKey, let urls = ProjectStore.stemURLs(key: key), !isAnalyzingTempo else { return }
        isAnalyzingTempo = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { await Self.analyzeTempo(urls: urls) }.value
            isAnalyzingTempo = false
            guard currentProjectKey == key, let result else { return }
            playback.beatGrid = result
            ProjectStore.saveBeatGrid(key: key, grid: result)
            if result == nil {
                alertMessage = "Hittade inget tydligt tempo i låten."
            }
        }
    }

    private func updateGrid(_ change: (BeatGrid) -> BeatGrid) {
        guard let grid = playback.beatGrid, let key = currentProjectKey else { return }
        let updated = change(grid)
        playback.beatGrid = updated
        ProjectStore.saveBeatGrid(key: key, grid: updated)
    }

    var tempoDescription: String {
        if isAnalyzingTempo { return "Analyserar tempo…" }
        guard let grid = playback.beatGrid else { return "Tempo okänt" }
        let whole = grid.bpm.rounded()
        let bpm = abs(grid.bpm - whole) < 0.05 ? String(Int(whole)) : String(format: "%.1f", grid.bpm)
        return "\(bpm) BPM · \(grid.beatsPerBar)/4"
    }

    private func resetPlayer() {
        playback.unload()
        isAnalyzingTempo = false
        trackObservers.removeAll()
        stems = []
        currentProjectKey = nil
        exportedURL = nil
    }

    private func computeWaveforms(for tracks: [StemTrack]) async -> [StemKind: [Float]] {
        let inputs = tracks.map { ($0.kind, $0.url) }
        return await withTaskGroup(of: (StemKind, [Float]).self) { group in
            for (kind, url) in inputs {
                group.addTask { (kind, await WaveformComputer.peaks(for: url)) }
            }
            var result: [StemKind: [Float]] = [:]
            for await (kind, peaks) in group {
                result[kind] = peaks
            }
            return result
        }
    }

    // MARK: - Volym, mute och solo

    private func observeTracks() {
        trackObservers.removeAll()
        // objectWillChange skickas före ändringen — vänta ett varv så att värdena är satta.
        Publishers.MergeMany(stems.map { $0.objectWillChange })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyGains() }
            .store(in: &trackObservers)
        applyGains()
    }

    private func gain(for track: StemTrack, anySoloed: Bool) -> Float {
        MixMath.effectiveGain(volume: track.volume, muted: track.muted, soloed: track.soloed, anySoloed: anySoloed)
    }

    private func applyGains() {
        let anySoloed = stems.contains { $0.soloed }
        if self.anySoloed != anySoloed { self.anySoloed = anySoloed }
        for track in stems {
            playback.setGain(track.kind, gain(for: track, anySoloed: anySoloed))
        }
    }

    func resetMix() {
        for track in stems {
            track.volume = 1
            track.muted = false
            track.soloed = false
        }
    }

    // MARK: - Export

    func exportMix() {
        guard isReady, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = (title ?? "mix") + " (mix).wav"
        panel.message = "Spara mixen med aktuella volymer, mute/solo, tonläge och tempo"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.startExport(to: url) }
        }
    }

    private func startExport(to url: URL) {
        let anySoloed = stems.contains { $0.soloed }
        let inputs = stems.map { MixerExporter.StemInput(url: $0.url, gain: gain(for: $0, anySoloed: anySoloed)) }
        let pitch = playback.pitchSemitones
        let tempo = playback.tempo
        isExporting = true
        exportProgress = 0
        exportedURL = nil
        exportTask = Task {
            do {
                try await MixerExporter.exportMix(stems: inputs, to: url, pitchSemitones: pitch, tempo: tempo) { value in
                    Task { @MainActor in self.exportProgress = value }
                }
                exportedURL = url
            } catch is CancellationError {
                // Avbruten av användaren — den halvfärdiga filen är redan borttagen.
            } catch {
                alertMessage = "Exporten misslyckades: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func revealExport() {
        guard let exportedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
    }

    // MARK: - Bibliotek och cache

    func refreshLibrary() {
        library = ProjectStore.list()
        cacheSize = ProjectStore.totalSize()
    }

    func deleteProject(_ key: String) {
        if key == currentProjectKey {
            cancelWork()
            resetPlayer()
            title = nil
            phase = .idle
        }
        ProjectStore.delete(key: key)
        refreshLibrary()
    }

    func revealProject(_ key: String) {
        NSWorkspace.shared.activateFileViewerSelecting([ProjectStore.directory(for: key)])
    }

    func clearCache() {
        cancelWork()
        resetPlayer()
        title = nil
        phase = .idle
        ProjectStore.clearAll()
        refreshLibrary()
    }

    func revealAppSupport() {
        NSWorkspace.shared.activateFileViewerSelecting([SeparationService.appSupportRoot])
    }

    // MARK: - Python

    func installPython() {
        showPythonInstallPrompt = false
        startLoad { id in
            self.phase = .working
            self.statusMessage = "Laddar ner Python 3.12 från python.org…"
            self.progressFraction = 0
            do {
                let package = try await PythonInstaller.download { fraction in
                    Task { @MainActor in
                        guard self.isCurrent(id) else { return }
                        self.progressFraction = fraction
                        self.statusMessage = "Laddar ner Python 3.12… \(Int(fraction * 100)) %"
                    }
                }
                guard self.isCurrent(id) else { return }
                PythonInstaller.openInstaller(at: package)
                self.phase = .idle
                self.progressFraction = nil
                self.alertMessage = "Slutför installationen i Installer och öppna sedan ljudfilen igen."
            } catch {
                guard self.isCurrent(id), !(error is CancellationError) else { return }
                self.phase = .failed("Kunde inte ladda ner Python: \(error.localizedDescription)")
            }
        }
    }
}
