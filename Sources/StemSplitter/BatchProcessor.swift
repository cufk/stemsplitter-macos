import Foundation
import StemSplitterAudio
import StemSplitterCore

/// Ser till att bara en Demucs-körning pågår åt gången (kön och en enskild låt delar GPU:n).
actor SeparationGate {
    static let shared = SeparationGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

func withSeparationGate<T>(_ body: () async throws -> T) async rethrows -> T {
    await SeparationGate.shared.acquire()
    do {
        let value = try await body()
        await SeparationGate.shared.release()
        return value
    } catch {
        await SeparationGate.shared.release()
        throw error
    }
}

/// Separerar flera låtar efter varandra i bakgrunden och lägger dem i biblioteket.
/// Vågformer och tempo räknas fram direkt, så att en klar låt öppnas utan väntan.
@MainActor
final class BatchProcessor: ObservableObject {
    @Published private(set) var queue = BatchQueue()
    /// Kön väntar (t.ex. på att Python installeras).
    @Published private(set) var isPaused = false

    /// Anropas när en låt finns i biblioteket (nyss separerad eller redan där).
    var onProjectReady: (String) -> Void = { _ in }
    var onNeedsPython: () -> Void = {}

    private let separator: SeparationService
    private var runTask: Task<Void, Never>?
    private var itemTask: Task<Void, Never>?

    init(separator: SeparationService) {
        self.separator = separator
    }

    var hasItems: Bool { !queue.items.isEmpty }
    var isActive: Bool { queue.isActive }

    @discardableResult
    func enqueue(_ urls: [URL]) -> Int {
        let added = queue.add(urls)
        log("Kö: \(added) låt(ar) tillagda, \(queue.counted.count - queue.finishedCount) kvar")
        startIfNeeded()
        return added
    }

    func resume() {
        isPaused = false
        startIfNeeded()
    }

    func cancel(_ id: UUID) {
        if queue.cancel(id) {
            log("Kö: avbryter pågående låt")
            itemTask?.cancel()
        }
    }

    func cancelAll() {
        log("Kö: avbryter alla")
        queue.cancelAll()
        itemTask?.cancel()
    }

    func clearFinished() { queue.clearFinished() }
    func remove(_ id: UUID) { queue.remove(id) }

    private func startIfNeeded() {
        guard runTask == nil, !isPaused, queue.next != nil else { return }
        runTask = Task { await run() }
    }

    private func run() async {
        defer { runTask = nil }
        guard await PythonLocator.find() != nil else {
            log("Kö: ingen Python 3.9–3.12 — kön pausas")
            isPaused = true
            onNeedsPython()
            return
        }
        while let item = queue.next, !isPaused {
            let task = Task { await self.process(item) }
            itemTask = task
            await task.value
            itemTask = nil
        }
        log("Kö: klar (\(queue.finishedCount) av \(queue.counted.count))")
    }

    private func process(_ item: BatchItem) async {
        let id = item.id
        let input = item.url
        log("Kö: börjar med \(input.lastPathComponent)")
        queue.update(id, to: .working(stage: .reading, progress: nil))
        do {
            let key = try await Task.detached(priority: .utility) {
                try CacheKey.fingerprint(of: input)
            }.value
            if ProjectStore.stemURLs(key: key) != nil {
                log("Kö: \(input.lastPathComponent) finns redan i biblioteket")
                queue.update(id, to: .alreadyInLibrary(key: key))
                onProjectReady(key)
                return
            }
            queue.update(id, to: .working(stage: .preparing, progress: nil))
            let model = SeparationModel.from(defaultsValue: UserDefaults.standard.string(forKey: SeparationModel.defaultsKey))
            let separator = self.separator
            let result = try await withSeparationGate {
                try Task.checkCancellation()
                return try await separator.separate(input: input, model: model.rawValue) { [weak self] event in
                    Task { @MainActor in self?.apply(event, to: id) }
                }
            }
            defer { try? FileManager.default.removeItem(at: result.workDirectory) }
            try Task.checkCancellation()
            queue.update(id, to: .working(stage: .saving, progress: nil))
            try ProjectStore.save(key: key, source: input, model: result.model, stems: result.stems)
            await ProjectPrecompute.run(key: key)
            log("Kö: \(input.lastPathComponent) klar (\(key))")
            queue.update(id, to: .done(key: key))
            onProjectReady(key)
        } catch {
            if error is CancellationError || Task.isCancelled {
                log("Kö: \(input.lastPathComponent) avbruten")
                queue.update(id, to: .cancelled)
            } else {
                log("Kö: \(input.lastPathComponent) misslyckades: \(error.localizedDescription)")
                queue.update(id, to: .failed(error.localizedDescription))
            }
        }
    }

    private func apply(_ event: SeparationService.Progress, to id: UUID) {
        switch event {
        case .preparing, .downloadingModel:
            queue.update(id, to: .working(stage: .preparing, progress: nil))
        case .converting(let fraction):
            queue.update(id, to: .working(stage: .converting, progress: fraction))
        case .separating(let fraction, _, _, _):
            queue.update(id, to: .working(stage: .separating, progress: fraction))
        case .retryingOnCPU:
            queue.update(id, to: .working(stage: .separating, progress: nil))
        }
    }
}

/// Räknar fram vågformer och tempo för ett projekt och sparar dem i project.json.
enum ProjectPrecompute {
    nonisolated static func run(key: String) async {
        guard let urls = ProjectStore.stemURLs(key: key) else { return }
        let peaks = await withTaskGroup(of: (StemKind, [Float]).self) { group in
            for (kind, url) in urls {
                group.addTask { (kind, await WaveformComputer.peaks(for: url)) }
            }
            var result: [StemKind: [Float]] = [:]
            for await (kind, values) in group { result[kind] = values }
            return result
        }
        ProjectStore.savePeaks(key: key, peaks: peaks)
        for kind in [StemKind.drums, .other, .bass] {
            guard let url = urls[kind] else { continue }
            if let grid = await BeatAnalyzer.analyze(url: url) {
                ProjectStore.saveBeatGrid(key: key, grid: grid)
                return
            }
        }
    }
}
