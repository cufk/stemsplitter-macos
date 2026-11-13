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
