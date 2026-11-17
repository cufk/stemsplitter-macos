import Foundation
import StemSplitterAudio
import StemSplitterCore

final class SeparationService: @unchecked Sendable {
    enum SeparationError: LocalizedError {
        case pythonMissing
        case bootstrapMissing
        case bootstrapFailed(Int32, String)
        case demucsFailed(Int32, String)
        case noStemsFound

        var errorDescription: String? {
            switch self {
            case .pythonMissing:
                return "Hittade ingen Python 3.9–3.12. Appen kan ladda ner och installera Python 3.12 från python.org åt dig."
            case .bootstrapMissing:
                return "Installationsskriptet saknas i appen. Bygg om appen."
            case .bootstrapFailed(let status, let tail):
                return "Kunde inte installera beroenden i den lokala Python-miljön (exitkod \(status)). Kontrollera internetanslutningen. Senaste loggrader:\n\(tail)"
            case .demucsFailed(let status, let tail):
                return "Demucs avslutades med fel (exitkod \(status)). Senaste loggrader:\n\(tail)"
            case .noStemsFound:
                return "Demucs gav inte alla fyra stems (sång, trummor, bas, övrigt)."
            }
        }
    }

    /// Förlopp under separeringen.
    enum Progress: Sendable {
        case preparing(String)
        case converting(Double)
        case separating(Double?, onGPU: Bool)
        case retryingOnCPU
    }

    struct Result {
        /// Arbetskatalog som anroparen ska ta bort när stems har flyttats.
        let workDirectory: URL
        let stems: [StemKind: URL]
        let model: String
    }

    static var appSupportRoot: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("StemSplitter", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var venvURL: URL {
        appSupportRoot.appendingPathComponent("venv", isDirectory: true)
    }

    private static let workPrefix = "separation-"

    /// Tar bort arbetskataloger som blivit kvar om appen avslutades mitt i en separering.
    static func removeStaleWorkDirectories() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: appSupportRoot, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix(workPrefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    private var demucsURL: URL { Self.venvURL.appendingPathComponent("bin/demucs") }
    private var venvPythonURL: URL { Self.venvURL.appendingPathComponent("bin/python") }
    private var installMarker: URL { Self.appSupportRoot.appendingPathComponent("deps-installed.flag") }
    private var deviceFile: URL { Self.appSupportRoot.appendingPathComponent("device.txt") }

    private static let environment = [
        "PYTHONUNBUFFERED": "1",
        // demucs 4.0.1 + torch >= 2.6: undvik weights_only-fel vid modell-laddning
        "TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD": "1"
    ]

    func separate(
        input: URL,
        model: String = "htdemucs",
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws -> Result {
        try await ensureEnvironment { message in progress(.preparing(message)) }

        let fileManager = FileManager.default
        let workDirectory = Self.appSupportRoot.appendingPathComponent("\(Self.workPrefix)\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        do {
            // Alltid till 44,1 kHz stereo-WAV: demucs/torchaudio saknar ofta mp3-stöd, och stems
            // blir då exakt lika långa som mixen så att "Övrigt" kan räknas fram nedan.
            progress(.converting(0))
            log("Gör om \(input.lastPathComponent) till 44,1 kHz stereo-WAV")
            let demucsInput = try await Task.detached(priority: .userInitiated) {
                let throttle = LockedThrottle()
                return try AudioConverter.wavCopy(of: input, in: workDirectory) { value in
                    if throttle.accept(value) { progress(.converting(value)) }
                }
            }.value
            log("Ljudfilen förberedd")
            let outputDirectory = workDirectory.appendingPathComponent("out", isDirectory: true)

            let device = await detectDevice()
            do {
                try await runDemucs(model: model, device: device, input: demucsInput, output: outputDirectory, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch where device == "mps" {
                // MPS kan sakna stöd för vissa operationer i htdemucs — kör om på CPU
                log("Demucs på GPU (MPS) misslyckades — kör om på CPU")
                progress(.retryingOnCPU)
                try? fileManager.removeItem(at: outputDirectory)
                try? "cpu".write(to: deviceFile, atomically: true, encoding: .utf8)
                try await runDemucs(model: model, device: "cpu", input: demucsInput, output: outputDirectory, progress: progress)
            }

            let located = try StemLocator.locate(in: outputDirectory)
            guard let vocals = located[.vocals], let drums = located[.drums],
                  let bass = located[.bass], let other = located[.other] else {
                log("Demucs gav bara: \(located.keys.map(\.rawValue).sorted())")
                throw SeparationError.noStemsFound
            }

            // "Övrigt" = originalet minus sång, trummor och bas. Då försvinner inget av ljudbilden:
            // det som Demucs inte placerade i någon stem hamnar här.
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try StemResidual.rebuild(target: other, mix: demucsInput, subtract: [vocals, drums, bass])
                }.value
                log(String(format: "Övrigt kompletterat — det som saknades låg på %.1f dB relativt originalet", report.missingLevel))
            } catch {
                // Inte kritiskt: Demucs egen "övrigt" används
                log("Kunde inte komplettera Övrigt: \(error.localizedDescription)")
            }
            return Result(workDirectory: workDirectory, stems: located, model: model)
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    private func runDemucs(
        model: String,
        device: String,
        input: URL,
        output: URL,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        let onGPU = device == "mps"
        progress(.separating(nil, onGPU: onGPU))
        log("Startar demucs -n \(model) -d \(device) \(input.lastPathComponent)")
        let throttle = LockedThrottle()
        do {
            try await ProcessRunner.run(
                executable: demucsURL,
                // --float32: ingen avrundning till 16 bitar och ingen omskalning av stems som klipper
                // (omskalning skulle ändra balansen mellan stems så att summan inte blir originalet)
                arguments: ["-n", model, "-d", device, "--float32", "-o", output.path, input.path],
                environment: Self.environment,
                onLine: { line in
                    if let fraction = ProgressParser.fraction(fromLine: line) {
                        if throttle.accept(fraction) { progress(.separating(fraction, onGPU: onGPU)) }
                        if throttle.shouldLog(fraction) { log("demucs \(Int(fraction * 100)) %") }
                    } else {
                        log("demucs: \(line)")
                    }
                }
            )
            log("Demucs klar")
        } catch let failure as ProcessRunner.Failure {
            log("Demucs avslutades med exitkod \(failure.status):\n\(failure.tail)")
            throw SeparationError.demucsFailed(failure.status, failure.tail)
        }
    }

    /// Välj mps (Apple Silicon-GPU) om tillgängligt, annars cpu. Cachas i device.txt.
    private func detectDevice() async -> String {
        if let cached = try? String(contentsOf: deviceFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), ["mps", "cpu"].contains(cached) {
            return cached
        }
        let lines = try? await ProcessRunner.run(
            executable: venvPythonURL,
            arguments: ["-c", "import torch; print('mps' if torch.backends.mps.is_available() else 'cpu')"],
            environment: Self.environment
        )
        let detected = lines?.last.flatMap { ["mps", "cpu"].contains($0) ? $0 : nil } ?? "cpu"
        log("Beräkningsenhet: \(detected)")
        try? detected.write(to: deviceFile, atomically: true, encoding: .utf8)
        return detected
    }

    private func ensureEnvironment(progress: @escaping @Sendable (String) -> Void) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: installMarker.path),
           fileManager.isExecutableFile(atPath: demucsURL.path) {
            return
        }
        guard let python = await PythonLocator.find() else {
            throw SeparationError.pythonMissing
        }
        guard let script = Bundle.module.url(forResource: "bootstrap", withExtension: "sh") else {
            throw SeparationError.bootstrapMissing
        }
        progress("Installerar Demucs i en lokal Python-miljö (flera minuter första gången)…")
        log("Installerar Demucs med \(python.path) (\(python.major).\(python.minor))")
        do {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [script.path, Self.venvURL.path],
                environment: Self.environment.merging(["PYTHON_BIN": python.path]) { _, new in new },
                onLine: { line in
                    if !line.contains("%|") && !line.contains("MB/s") { log("bootstrap: \(line)") }
                    progress(line)
                }
            )
            log("Demucs installerat")
        } catch let failure as ProcessRunner.Failure {
            log("Installationen misslyckades (exitkod \(failure.status)):\n\(failure.tail)")
            throw SeparationError.bootstrapFailed(failure.status, failure.tail)
        }
        try? fileManager.removeItem(at: deviceFile)
        fileManager.createFile(atPath: installMarker.path, contents: Data(Date().description.utf8))
    }
}

/// Trådsäker strypning av förloppet från processens utdata (anropas från en bakgrundskö).
private final class LockedThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var ui = ProgressThrottle(step: 0.01)
    private var lastLogged = -1

    func accept(_ value: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ui.accept(value)
    }

    /// Loggar var tionde procent.
    func shouldLog(_ value: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let decile = Int(value * 10)
        guard decile != lastLogged else { return false }
        lastLogged = decile
        return true
    }
}
