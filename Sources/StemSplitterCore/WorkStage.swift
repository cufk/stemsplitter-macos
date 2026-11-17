import Foundation

/// Stegen när en ny låt bearbetas, i den ordning de visas.
public enum WorkStage: Int, CaseIterable, Sendable, Comparable {
    case reading
    case preparing
    case converting
    case separating
    case saving

    public var title: String {
        switch self {
        case .reading: return "Läser filen"
        case .preparing: return "Förbereder AI-miljön"
        case .converting: return "Konverterar till WAV"
        case .separating: return "Delar upp i stems"
        case .saving: return "Sparar"
        }
    }

    /// Steg som visas för en fil; WAV behöver ingen konvertering.
    public static func stages(for fileExtension: String) -> [WorkStage] {
        let needsConversion = fileExtension.lowercased() != "wav"
        return allCases.filter { $0 != .converting || needsConversion }
    }

    public static func < (lhs: WorkStage, rhs: WorkStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Släpper bara igenom förloppsvärden som ändrats med minst `step` (minskar UI-uppdateringar och loggrader).
public struct ProgressThrottle: Sendable {
    public let step: Double
    private var last: Double?

    public init(step: Double = 0.01) {
        self.step = step
    }

    public mutating func accept(_ value: Double) -> Bool {
        if let last, abs(value - last) < step, value < 1 { return false }
        last = value
        return true
    }
}
