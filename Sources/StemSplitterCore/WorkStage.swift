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
        case .converting: return "Förbereder ljudfilen"
        case .separating: return "Delar upp i stems"
        case .saving: return "Sparar"
        }
    }

    /// Alla filer (även WAV) görs om till 44,1 kHz stereo först, så att stems och original
    /// blir exakt lika långa och "Övrigt" kan räknas fram som originalet minus övriga stems.
    public static var all: [WorkStage] { allCases }

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
