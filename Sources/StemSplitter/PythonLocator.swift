import Foundation
import StemSplitterCore

enum PythonLocator {
    static let minimum = (major: 3, minor: 9)

    struct Found {
        let path: String
        let version: (major: Int, minor: Int)
    }

    private static let candidatePaths = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
        "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
        "/usr/bin/python3"
    ]

    static func find() async -> Found? {
        if let found = await probe(executable: "/usr/bin/env", arguments: ["python3"], reportedPath: "python3") {
            return found
        }
        for path in candidatePaths {
            if let found = await probe(executable: path, arguments: [], reportedPath: path) {
                return found
            }
        }
        return nil
    }

    private static func probe(executable: String, arguments: [String], reportedPath: String) async -> Found? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = executable
            process.arguments = arguments + ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else {
                continuation.resume(returning: nil)
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8),
                  PythonVersion.isCompatible(output, minimum: minimum),
                  let version = PythonVersion.parse(output)
            else {
                continuation.resume(returning: nil)
                return
            }
            continuation.resume(returning: Found(path: reportedPath, version: version))
        }
    }
}
