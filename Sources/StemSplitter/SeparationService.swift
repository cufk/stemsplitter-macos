import Foundation
import StemSplitterCore

final class SeparationService {
    enum SeparationError: LocalizedError {
        case pythonMissing
        case bootstrapFailed(Int32, String)
        case demucsFailed(Int32, String)
        case noStemsFound

        var errorDescription: String? {
            switch self {
            case .pythonMissing:
                return "Hittade ingen Python 3.9+. Appen kan ladda ner och installera Python från python.org åt dig."
            case .bootstrapFailed(let status, let tail):
                return "Kunde inte installera beroenden i den lokala Python-miljön (exitkod \(status)). Kontrollera internetanslutningen. Senaste loggrader:\n\(tail)"
            case .demucsFailed(let status, let tail):
                return "Demucs avslutades med fel (exitkod \(status)). Senaste loggrader:\n\(tail)"
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

    private var pythonPath: String?

    private func ensurePython() async throws -> String {
        if let pythonPath { return pythonPath }
        guard let found = await PythonLocator.find() else {
            throw SeparationError.pythonMissing
        }
        pythonPath = found.path
        return found.path
    }

    private var deviceFile: URL {
        Self.appSupportRoot.appendingPathComponent("device.txt")
    }

    /// Välj mps (Apple Silicon GPU) om tillgängligt, annars cpu. Cachat i device.txt.
    private func detectDevice() async -> String {
        if let cached = try? String(contentsOf: deviceFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !cached.isEmpty {
            return cached
        }
        let python = venvURL.appendingPathComponent("bin/python").path
        let detected: String
        if let output = try? await captureOutput(
            launchPath: python,
            arguments: ["-c", "import torch; print('mps' if torch.backends.mps.is_available() else 'cpu')"]
        ), let last = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last,
           ["mps", "cpu"].contains(last) {
            detected = String(last)
        } else {
            detected = "cpu"
        }
        try? detected.data(using: .utf8)?.write(to: deviceFile)
        return detected
    }

    func separate(input: URL, model: String = "htdemucs", progress: @escaping (String, Double?) -> Void) async throws -> [StemKind: URL] {
        try await ensureEnvironment { message in progress(message, nil) }

        let outputDir = Self.appSupportRoot.appendingPathComponent("separation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // demucs/torchaudio saknar ofta ffmpeg/mp3-stöd — konvertera till WAV först (utom om redan WAV)
        let demucsInput: URL
        if input.pathExtension.lowercased() == "wav" {
            demucsInput = input
        } else {
            progress("Konverterar till WAV…", nil)
            demucsInput = try AudioConverter.wavCopy(of: input)
        }

        func runDemucs(device: String) async throws {
            progress("Separerar stems med \(model) på \(device)…", nil)
            try await runStreaming(
                launchPath: demucsPath,
                arguments: ["-n", model, "-d", device, "-o", outputDir.path, demucsInput.path],
                progress: { line in progress(line, ProgressParser.fraction(fromLine: line)) },
                failure: { status, tail in SeparationError.demucsFailed(status, tail) }
            )
        }

        let device = await detectDevice()
        do {
            try await runDemucs(device: device)
        } catch {
            // MPS kan sakna stöd för vissa opar i htdemucs — fall tillbaka på CPU
            if device == "mps" {
                progress("MPS funkade inte — kör om på CPU…", nil)
                try? FileManager.default.removeItem(at: deviceFile)
                try await runDemucs(device: "cpu")
            } else {
                throw error
            }
        }

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
        let python = try await ensurePython()
        guard let script = Bundle.module.url(forResource: "bootstrap", withExtension: "sh") else {
            throw SeparationError.pythonMissing
        }
        progress("Skapar lokal Python-miljö och installerar Demucs (kan ta flera minuter första gången)…")
        try await runStreaming(
            launchPath: "/bin/sh",
            arguments: [script.path, venvURL.path],
            progress: progress,
            extraEnv: ["PYTHON_BIN": python],
            failure: { status, tail in SeparationError.bootstrapFailed(status, tail) }
        )
        fileManager.createFile(atPath: installMarker.path, contents: Date().description.data(using: .utf8))
    }

    private func runStreaming(
        launchPath: String,
        arguments: [String],
        progress: @escaping (String) -> Void,
        extraEnv: [String: String] = [:],
        failure: @escaping (Int32, String) -> Error
    ) async throws {
        let process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        // demucs 4.0.1 + torch >=2.6: undvik weights_only-fel vid modell-laddning
        environment["TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD"] = "1"
        for (key, value) in extraEnv {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var buffer = Data()
            var tail: [String] = []
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
                        box.resume(throwing: failure(status, tail.suffix(30).joined(separator: "\n")))
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
                            let isProgressSpam = trimmed.contains("%|") || trimmed.contains("MB/s") || trimmed.contains("it/s]") || trimmed.contains("s/it]")
                            if !isProgressSpam {
                                tail.append(trimmed)
                                if tail.count > 30 {
                                    tail.removeFirst(tail.count - 30)
                                }
                            }
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
                        continuation.resume(throwing: SeparationError.pythonMissing)
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
