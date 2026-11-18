import Foundation
import StemSplitterCore

enum PythonLocator {
    struct Found: Sendable {
        let path: String
        let major: Int
        let minor: Int
    }

    /// Letar efter en Python 3.9–3.12 på kända platser (inte via PATH, som är minimal för GUI-appar).
    static func find() async -> Found? {
        let includeSystem = await commandLineToolsInstalled()
        for path in PythonCandidates.paths(includeSystem: includeSystem)
        where FileManager.default.isExecutableFile(atPath: path) {
            if let found = await probe(path) {
                return found
            }
        }
        return nil
    }

    /// Utan utvecklarverktyg är /usr/bin/python3 en genväg som öppnar en installationsdialog.
    private static func commandLineToolsInstalled() async -> Bool {
        do {
            try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"])
            return true
        } catch {
            return false
        }
    }

    private static func probe(_ path: String) async -> Found? {
        guard let lines = try? await ProcessRunner.run(executable: URL(fileURLWithPath: path), arguments: ["--version"]) else {
            return nil
        }
        let output = lines.joined(separator: "\n")
        guard PythonVersion.isSupported(output), let version = PythonVersion.parse(output) else {
            return nil
        }
        return Found(path: path, major: version.major, minor: version.minor)
    }
}
