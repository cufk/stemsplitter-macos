import Foundation
import StemSplitterCore

final class SeparationService {
    enum SeparationError: LocalizedError {
        case noPython
        case pythonTooOld(String)
        case bootstrapFailed(Int32)
        case demucsFailed(Int32)
        case noStemsFound

        var errorDescription: String? {
            switch self {
            case .noPython:
                return "Hittade ingen python3. Installera Command Line Tools for Xcode (xcode-select --install) eller ett Python 3.9+-paket från python.org."
            case .pythonTooOld(let version):
                return "python3 \(version) är för gammal — StemSplitter behöver Python 3.9 eller nyare."
            case .bootstrapFailed(let status):
                return "Kunde inte installera beroenden i den lokala Python-miljön (exitkod \(status)). Kontrollera internetanslutningen och försök igen."
            case .demucsFailed(let status):
                return "Demucs avslutades med fel (exitkod \(status))."
            case .noStemsFound:
                return "Inga stem-filer hittades i utdatan från Demucs."
            }
        }
    }

    static var appSupportRoot: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("StemSplitter", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var venvURL: URL {
        Self.appSupportRoot.appendingPathComponent("venv", isDirectory: true)
    }

    private var demucsPath: String {
        venvURL.appendingPathComponent("bin/demucs").path
    }

    private var installMarker: URL {
        Self.appSupportRoot.appendingPathComponent("deps-installed.flag")
    }

    func separate(input: URL, model: String = "htdemucs", progress: @escaping (String, Double?) -> Void) async throws -> [StemKind: URL] {
        try await ensureEnvironment { message in progress(message, nil) }

        let outputDir = Self.appSupportRoot.appendingPathComponent("separation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        progress("Separerar stems med \(model)…", nil)
        try await runStreaming(
            launchPath: demucsPath,
            arguments: ["-n", model, "-o", outputDir.path, input.path],
            progress: { line in progress(line, ProgressParser.fraction(fromLine: line)) },
            failure: SeparationError.demucsFailed
        )

        let located = try StemLocator.locate(in: outputDir)
        guard !located.isEmpty else { throw SeparationError.noStemsFound }
        return located
    }

    private func ensureEnvironment(progress: @escaping (String) -> Void) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: installMarker.path),
           fileManager.fileExists(atPath: demucsPath) {
            return
        }
        try await checkPython()
        guard let script = Bundle.module.url(forResource: "bootstrap", withExtension: "sh") else {
            throw SeparationError.noPython
        }
        progress("Skapar lokal Python-miljö och installerar Demucs (kan ta flera minuter första gången)…")
        try await runStreaming(
            launchPath: "/bin/sh",
            arguments: [script.path, venvURL.path],
            progress: progress,
            failure: SeparationError.bootstrapFailed
        )
        fileManager.createFile(atPath: installMarker.path, contents: Date().description.data(using: .utf8))
    }

    private func checkPython() async throws {
        let version = try await captureOutput(
            launchPath: "/usr/bin/env",
            arguments: ["python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"]
        )
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 3 || (parts[0] == 3 && parts[1] >= 9) else {
            throw SeparationError.pythonTooOld(trimmed.isEmpty ? "okänd" : trimmed)
        }
    }

    private func runStreaming(
        launchPath: String,
        arguments: [String],
        progress: @escaping (String) -> Void,
        failure: @escaping (Int32) -> Error
    ) async throws {
        let process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var buffer = Data()
            let box = ContinuationBox(continuation: continuation)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    process.waitUntilExit()
                    let status = process.terminationStatus
                    if status == 0 {
                        box.resume()
                    } else {
                        box.resume(throwing: failure(status))
                    }
                    return
                }
                buffer.append(data)
                while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<index)
                    buffer.removeSubrange(buffer.startIndex...index)
                    if let line = String(data: lineData, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            progress(trimmed)
                        }
                    }
                }
            }
        }
    }

    private func captureOutput(launchPath: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var collected = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: String(data: collected, encoding: .utf8) ?? "")
                    } else {
                        continuation.resume(throwing: SeparationError.noPython)
                    }
                    return
                }
                collected.append(data)
            }
        }
    }

    private final class ContinuationBox {
        private var continuation: CheckedContinuation<Void, Error>?

        init(continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func resume() {
            continuation?.resume(returning: ())
            continuation = nil
        }

        func resume(throwing error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
