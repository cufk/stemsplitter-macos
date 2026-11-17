import Foundation

/// Håller reda på startade underprocesser så att de kan avslutas när appen stängs.
final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func add(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = process
    }

    func remove(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes.removeValue(forKey: ObjectIdentifier(process))
    }

    func terminateAll() {
        lock.lock()
        let running = Array(processes.values)
        lock.unlock()
        for process in running where process.isRunning {
            process.terminate()
        }
    }
}

/// Kör en extern process, strömmar dess utdata rad för rad och stöder avbrytning via Task.cancel().
enum ProcessRunner {
    struct Failure: Error {
        let status: Int32
        let tail: String
    }

    /// - Returns: de sista (högst 30) icke-progress-raderna av utdatan.
    /// - Throws: `Failure` vid exitkod ≠ 0, `CancellationError` om tasken avbröts.
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        environment extra: [String: String] = [:],
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [String] {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extra {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let state = RunState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
                state.setContinuation(continuation)
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        process.waitUntilExit()
                        ProcessRegistry.shared.remove(process)
                        for line in state.flush() { onLine(line) }
                        state.finish(status: process.terminationStatus)
                        return
                    }
                    for line in state.append(data) { onLine(line) }
                }
                do {
                    try process.run()
                    ProcessRegistry.shared.add(process)
                    if state.isCancelled { process.terminate() }
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    state.fail(error)
                }
            }
        } onCancel: {
            state.markCancelled()
            if process.isRunning { process.terminate() }
        }
    }

    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String], Error>?
        private var buffer = Data()
        private var tail: [String] = []
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        func setContinuation(_ continuation: CheckedContinuation<[String], Error>) {
            lock.lock(); defer { lock.unlock() }
            self.continuation = continuation
        }

        func markCancelled() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
        }

        /// Lägger till data och returnerar kompletta rader (avgränsade av \n eller \r).
        func append(_ data: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            buffer.append(data)
            var lines: [String] = []
            while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let lineData = buffer.subdata(in: buffer.startIndex..<index)
                buffer.removeSubrange(buffer.startIndex...index)
                if let line = record(lineData) { lines.append(line) }
            }
            return lines
        }

        func flush() -> [String] {
            lock.lock(); defer { lock.unlock() }
            let rest = buffer
            buffer = Data()
            return record(rest).map { [$0] } ?? []
        }

        private func record(_ data: Data) -> String? {
            guard let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
            let isProgressSpam = line.contains("%|") || line.contains("MB/s")
                || line.contains("it/s]") || line.contains("s/it]")
            if !isProgressSpam {
                tail.append(line)
                if tail.count > 30 { tail.removeFirst(tail.count - 30) }
            }
            return line
        }

        func finish(status: Int32) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            let wasCancelled = cancelled
            let lines = tail
            lock.unlock()
            if wasCancelled {
                continuation?.resume(throwing: CancellationError())
            } else if status == 0 {
                continuation?.resume(returning: lines)
            } else {
                continuation?.resume(throwing: Failure(status: status, tail: lines.joined(separator: "\n")))
            }
        }

        func fail(_ error: Error) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(throwing: error)
        }
    }
}
