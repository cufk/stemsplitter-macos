import Foundation

public enum ProgressParser {
    private static let percentRegex = try? NSRegularExpression(pattern: #"(\d{1,3})\s?%"#)
    private static let megabytesRegex = try? NSRegularExpression(pattern: #"([\d.]+)\s*/\s*([\d.]+)\s*MB"#)

    public static func fraction(fromLine line: String) -> Double? {
        if let regex = percentRegex,
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line),
           let value = Int(line[range]) {
            return Double(min(100, max(0, value))) / 100.0
        }
        // pip/tqdm utan procent: "63.9/63.9 MB"
        if let regex = megabytesRegex,
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let currentRange = Range(match.range(at: 1), in: line),
           let totalRange = Range(match.range(at: 2), in: line),
           let current = Double(line[currentRange]),
           let total = Double(line[totalRange]),
           total > 0 {
            return min(1, max(0, current / total))
        }
        return nil
    }
}

/// Vad en rad från Demucs betyder för förloppet.
public enum DemucsLine: Equatable, Sendable {
    /// Nedladdning av modellvikter (första gången en modell används): "80.2M/80.2M [00:05, 15.2MB/s]".
    case download(Double)
    /// Separering: "45%|████ | 78.0/175.5 [00:10<00:12, 7.81seconds/s]".
    case separation(Double)
    case other
}

extension ProgressParser {
    public static func classify(_ line: String) -> DemucsLine {
        guard let fraction = fraction(fromLine: line) else { return .other }
        if line.contains("seconds") { return .separation(fraction) }
        if line.contains("B/s") || line.contains("Downloading") { return .download(fraction) }
        return .separation(fraction)
    }
}

/// Slår ihop flera omgångar som var och en går 0→100 % till ett enda förlopp.
/// Demucs kör t.ex. fyra modeller efter varandra för htdemucs_ft, med ett eget förlopp per modell.
/// En ny omgång känns igen på att procenten börjar om.
public struct PassProgress: Sendable {
    public private(set) var passIndex = 0
    public private(set) var passes: Int
    private var last: Double?

    public init(expectedPasses: Int) {
        passes = max(1, expectedPasses)
    }

    /// Omgång som pågår, räknat från 1.
    public var passNumber: Int { passIndex + 1 }

    /// Tar emot förloppet för aktuell omgång (0…1) och returnerar det samlade förloppet (0…1).
    public mutating func update(_ fraction: Double) -> Double {
        let value = min(max(fraction, 0), 1)
        if let last, value < last - 0.2 {
            passIndex += 1
            // Fler omgångar än väntat: utöka hellre än att gå över 100 %
            passes = max(passes, passIndex + 1)
        }
        last = value
        return min(1, (Double(passIndex) + value) / Double(passes))
    }
}
