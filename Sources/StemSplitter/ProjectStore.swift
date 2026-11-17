import Foundation
import StemSplitterCore

struct ProjectSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let createdAt: Date
}

/// Cachade separeringar: projects/<nyckel>/{vocals,drums,bass,other}.wav + project.json.
enum ProjectStore {
    enum StoreError: LocalizedError {
        case incomplete

        var errorDescription: String? {
            "Projektet saknar stem-filer. Ta bort det och separera låten igen."
        }
    }

    static var root: URL {
        let dir = SeparationService.appSupportRoot.appendingPathComponent("projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let stagingPrefix = ".staging-"

    static func directory(for key: String) -> URL {
        root.appendingPathComponent(key, isDirectory: true)
    }

    /// Alla fyra stems om projektet är komplett, annars nil.
    static func stemURLs(key: String) -> [StemKind: URL]? {
        let dir = directory(for: key)
        var result: [StemKind: URL] = [:]
        for kind in StemKind.allCases {
            let url = dir.appendingPathComponent("\(kind.rawValue).wav")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            result[kind] = url
        }
        return result
    }

    static func meta(key: String) -> ProjectMeta? {
        let url = directory(for: key).appendingPathComponent(ProjectMeta.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ProjectMeta.decode(data)
    }

    /// Flyttar stems till ett nytt projekt. Atomiskt: projektet syns först när allt är på plats,
    /// så ett avbrutet försök lämnar aldrig ett halvfärdigt projekt efter sig.
    static func save(key: String, source: URL, model: String, stems: [StemKind: URL]) throws {
        let fileManager = FileManager.default
        guard StemKind.allCases.allSatisfy({ stems[$0] != nil }) else { throw StoreError.incomplete }
        let staging = root.appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (kind, url) in stems {
                try fileManager.moveItem(at: url, to: staging.appendingPathComponent("\(kind.rawValue).wav"))
            }
            let meta = ProjectMeta(sourceName: source.lastPathComponent, createdAt: Date(), model: model, sourcePath: source.path)
            try meta.encoded().write(to: staging.appendingPathComponent(ProjectMeta.fileName), options: .atomic)
            let destination = directory(for: key)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    static func savePeaks(key: String, peaks: [StemKind: [Float]]) {
        updateMeta(key: key) { meta in
            for (kind, values) in peaks {
                meta.peaks[kind.rawValue] = values
            }
        }
    }

    static func saveBeatGrid(key: String, grid: BeatGrid?) {
        updateMeta(key: key) { $0.beatGrid = grid }
    }

    private static func updateMeta(key: String, _ change: (inout ProjectMeta) -> Void) {
        var meta = meta(key: key) ?? ProjectMeta(sourceName: key, createdAt: Date(), model: "htdemucs")
        change(&meta)
        let url = directory(for: key).appendingPathComponent(ProjectMeta.fileName)
        try? meta.encoded().write(to: url, options: .atomic)
    }

    static func list() -> [ProjectSummary] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url -> ProjectSummary? in
            let key = url.lastPathComponent
            guard stemURLs(key: key) != nil else { return nil }
            if let meta = meta(key: key) {
                return ProjectSummary(id: key, name: meta.displayName, createdAt: meta.createdAt)
            }
            // Projekt från tidigare versioner saknar project.json
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return ProjectSummary(id: key, name: "Okänd låt", createdAt: created)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func delete(key: String) {
        try? FileManager.default.removeItem(at: directory(for: key))
    }

    static func clearAll() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for url in entries {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Tar bort halvfärdiga projekt som blivit kvar efter en krasch.
    static func removeStaleStaging() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix(stagingPrefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    static func totalSize() -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
