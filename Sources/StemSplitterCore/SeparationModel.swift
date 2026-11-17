import Foundation

/// Demucs-modell för separeringen.
public enum SeparationModel: String, CaseIterable, Sendable, Identifiable {
    /// Snabb, bra kvalitet.
    case standard = "htdemucs"
    /// Fyra finjusterade modeller — tydligare uppdelning, ungefär fyra gånger långsammare.
    case best = "htdemucs_ft"

    public static let defaultsKey = "separationModel"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Snabb"
        case .best: return "Bästa kvalitet"
        }
    }

    public var detail: String {
        switch self {
        case .standard: return "htdemucs — bra kvalitet, snabbast."
        case .best: return "htdemucs_ft — tydligare uppdelning, ungefär fyra gånger långsammare. Laddar ner modellen första gången."
        }
    }

    public static func from(defaultsValue: String?) -> SeparationModel {
        defaultsValue.flatMap(SeparationModel.init(rawValue:)) ?? .standard
    }
}
