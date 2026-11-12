import Foundation

public enum StemKind: String, CaseIterable, Sendable {
    case vocals
    case drums
    case bass
    case other

    public var displayName: String {
        switch self {
        case .vocals: return "Sång"
        case .drums: return "Trummor"
        case .bass: return "Bas"
        case .other: return "Övrigt"
        }
    }

    public init?(fileName: String) {
        let base = (fileName as NSString).deletingPathExtension.lowercased()
        guard let kind = StemKind(rawValue: base) else { return nil }
        self = kind
    }
}
