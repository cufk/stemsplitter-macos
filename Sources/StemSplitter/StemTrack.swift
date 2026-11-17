import Combine
import Foundation
import SwiftUI
import StemSplitterCore

final class StemTrack: ObservableObject, Identifiable {
    let kind: StemKind
    let url: URL
    var id: StemKind { kind }

    @Published var volume: Double = 1.0
    @Published var muted: Bool = false
    @Published var soloed: Bool = false
    @Published var waveform: [Float] = []

    init(kind: StemKind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

extension StemKind {
    /// Egen färg per stem — samma i ljust och mörkt läge, mättad nog för vågformer.
    var color: Color {
        switch self {
        case .vocals: return Color(red: 0.93, green: 0.33, blue: 0.16)   // orange (appens accent)
        case .drums: return Color(red: 0.96, green: 0.65, blue: 0.14)    // gul-orange
        case .bass: return Color(red: 0.55, green: 0.42, blue: 0.95)     // violett
        case .other: return Color(red: 0.16, green: 0.68, blue: 0.62)    // grön-turkos
        }
    }

    var symbolName: String {
        switch self {
        case .vocals: return "music.mic"
        case .drums: return "metronome"
        case .bass: return "guitars"
        case .other: return "pianokeys"
        }
    }
}
