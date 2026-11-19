import Foundation

/// En låt i bearbetningskön.
public struct BatchItem: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case waiting
        case working(stage: WorkStage, progress: Double?)
        case done(key: String)
        /// Låten fanns redan i biblioteket och behövde inte separeras.
        case alreadyInLibrary(key: String)
        case failed(String)
        case cancelled

        public var isFinished: Bool {
            switch self {
            case .waiting, .working: return false
            default: return true
            }
        }

        public var projectKey: String? {
            switch self {
            case .done(let key), .alreadyInLibrary(let key): return key
            default: return nil
            }
        }
    }

    public let id: UUID
    public let url: URL
    public var state: State

    public init(url: URL, id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.state = .waiting
    }

    public var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Kö för att separera flera låtar efter varandra. Ren logik — själva arbetet görs av appen.
public struct BatchQueue: Equatable, Sendable {
    public private(set) var items: [BatchItem] = []

    public init() {}

    /// Lägger till filer som inte redan väntar eller bearbetas. Returnerar antalet tillagda.
    @discardableResult
    public mutating func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            let path = url.standardizedFileURL.path
            let queued = items.contains { !$0.state.isFinished && $0.url.standardizedFileURL.path == path }
            if !queued {
                items.append(BatchItem(url: url))
                added += 1
            }
        }
        return added
    }

    /// Nästa låt som väntar.
    public var next: BatchItem? { items.first { $0.state == .waiting } }

    public var current: BatchItem? {
        items.first { if case .working = $0.state { return true } else { return false } }
    }

    public var isActive: Bool { items.contains { !$0.state.isFinished } }

    public mutating func update(_ id: UUID, to state: BatchItem.State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        // En avbruten låt ska inte återuppstå om ett sent förloppsbesked kommer in
        if items[index].state == .cancelled, !state.isFinished { return }
        items[index].state = state
    }

    /// Avbryter en låt som väntar eller bearbetas. Returnerar true om den bearbetades just nu.
    @discardableResult
    public mutating func cancel(_ id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].state.isFinished else { return false }
        let wasWorking: Bool
        if case .working = items[index].state { wasWorking = true } else { wasWorking = false }
        items[index].state = .cancelled
        return wasWorking
    }

    public mutating func cancelAll() {
        for index in items.indices where !items[index].state.isFinished {
            items[index].state = .cancelled
        }
    }

    /// Tar bort klara, misslyckade och avbrutna låtar ur listan.
    public mutating func clearFinished() {
        items.removeAll { $0.state.isFinished }
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id && $0.state.isFinished }
    }

    /// Låtar som räknas i förloppet (avbrutna räknas inte).
    public var counted: [BatchItem] { items.filter { $0.state != .cancelled } }

    public var finishedCount: Int { counted.filter { $0.state.isFinished }.count }

    /// Samlat förlopp 0…1 över alla låtar i kön, inklusive den som pågår.
    public var overallProgress: Double {
        let total = counted.count
        guard total > 0 else { return 0 }
        var sum = Double(finishedCount)
        if let current, case .working(let stage, let progress) = current.state {
            sum += Self.itemProgress(stage: stage, progress: progress)
        }
        return min(1, sum / Double(total))
    }

    /// Ungefärligt förlopp för en låt: separeringen är den stora delen av arbetet.
    public static func itemProgress(stage: WorkStage, progress: Double?) -> Double {
        let p = min(max(progress ?? 0, 0), 1)
        switch stage {
        case .reading: return 0
        case .preparing: return 0.02
        case .converting: return 0.02 + 0.08 * p
        case .separating: return 0.10 + 0.85 * p
        case .saving: return 0.95 + 0.05 * p
        }
    }
}

extension AudioFileSupport {
    /// Ljudfiler bland de givna adresserna; mappar söks igenom (även undermappar), sorterat efter namn.
    public static func collectAudioFiles(from urls: [URL], fileManager: FileManager = .default) -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let found = (fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])?
                    .compactMap { $0 as? URL } ?? [])
                    .filter { isSupported($0) }
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                result.append(contentsOf: found)
            } else if isSupported(url) {
                result.append(url)
            }
        }
        return result
    }
}
