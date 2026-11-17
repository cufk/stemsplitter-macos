import Foundation

public enum PythonVersion {
    /// Versioner som PyTorch-paketen i bootstrap.sh finns för (torch 2.5.1 / 2.2.2 på macOS).
    public static let supportedMinimum = (major: 3, minor: 9)
    public static let supportedMaximum = (major: 3, minor: 12)

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

    /// Inom intervallet som Demucs-miljön kan installeras för.
    public static func isSupported(_ versionOutput: String) -> Bool {
        guard let version = parse(versionOutput), isCompatible(versionOutput, minimum: supportedMinimum) else { return false }
        return version.major < supportedMaximum.major
            || (version.major == supportedMaximum.major && version.minor <= supportedMaximum.minor)
    }
}

/// Var appen letar efter Python. En app som startas från Finder har en minimal PATH,
/// så vi letar på kända platser i stället, med versionsspecifika binärer först.
public enum PythonCandidates {
    public static let preferredVersions = ["3.12", "3.11", "3.10", "3.9"]

    public static func paths(
        homebrewPrefixes: [String] = ["/opt/homebrew", "/usr/local"],
        includeSystem: Bool
    ) -> [String] {
        var result: [String] = []
        for version in preferredVersions {
            result.append("/Library/Frameworks/Python.framework/Versions/\(version)/bin/python3")
            for prefix in homebrewPrefixes {
                result.append("\(prefix)/bin/python\(version)")
            }
        }
        for prefix in homebrewPrefixes {
            result.append("\(prefix)/bin/python3")
        }
        // /usr/bin/python3 är bara en genväg som visar installationsdialogen
        // för utvecklarverktyg om de saknas — använd den bara när de finns.
        if includeSystem {
            result.append("/usr/bin/python3")
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }
}
