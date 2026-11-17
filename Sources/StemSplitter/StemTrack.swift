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
    var color: Color {
        switch self {
        case .vocals: return .pink
        case .drums: return .orange
        case .bass: return .purple
        case .other: return .teal
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
