import Foundation

public enum PythonVersion {
    public static func parse(_ versionOutput: String) -> (major: Int, minor: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)"#),
              let match = regex.firstMatch(in: versionOutput, range: NSRange(versionOutput.startIndex..., in: versionOutput)),
              let majorRange = Range(match.range(at: 1), in: versionOutput),
              let minorRange = Range(match.range(at: 2), in: versionOutput),
              let major = Int(versionOutput[majorRange]),
              let minor = Int(versionOutput[minorRange])
        else {
            return nil
        }
        return (major, minor)
    }

    public static func isCompatible(_ versionOutput: String, minimum: (major: Int, minor: Int) = (3, 9)) -> Bool {
        guard let version = parse(versionOutput) else { return false }
        return version.major > minimum.major
            || (version.major == minimum.major && version.minor >= minimum.minor)
    }
}
