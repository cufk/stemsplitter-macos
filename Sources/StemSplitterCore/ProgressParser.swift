import Foundation

public enum ProgressParser {
    private static let percentRegex = try? NSRegularExpression(pattern: #"(\d{1,3})\s?%"#)

    public static func fraction(fromLine line: String) -> Double? {
        guard let regex = percentRegex,
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Int(line[range])
        else {
            return nil
        }
        return Double(min(100, max(0, value))) / 100.0
    }
}
