import SwiftUI
import StemSplitterCore

/// Reglagen under spåren: volym per stem till vänster, övning (tempo, tonläge, klick) till höger.
struct MixerPanel: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Mix")
                ForEach(viewModel.stems) { track in
                    StemVolumeSlider(track: track)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Övning")
                PillSlider(
                    title: "Tempo",
                    value: $playback.tempo,
                    range: 0.5...2.0,
                    step: 0.05,
                    defaultValue: 1,
                    format: tempoText
                )
                PillSlider(
                    title: "Tonläge",
                    value: $playback.pitchSemitones,
                    range: -12...12,
                    step: 1,
                    defaultValue: 0,
                    format: { value in
                        let semitones = Int(value.rounded())
                        return semitones > 0 ? "+\(semitones) st" : "\(semitones) st"
                    }
                )
                PillSlider(
                    title: playback.clickEnabled ? "Klick" : "Klick (av)",
                    value: $playback.clickVolume,
                    range: 0...1,
                    defaultValue: 0.7,
                    isDisabled: playback.beatGrid == nil,
                    format: { "\(Int(($0 * 100).rounded())) %" }
                )
                .help(playback.beatGrid == nil ? "Klicket blir tillgängligt när tempot är analyserat" : "Slå på klicket med metronomknappen nedan")
            }
        }
    }

    private func tempoText(_ value: Double) -> String {
        let percent = "\(Int((value * 100).rounded())) %"
        guard let bpm = playback.beatGrid?.bpm else { return percent }
        return "\(Int((bpm * value).rounded())) BPM · \(percent)"
    }
}

private struct StemVolumeSlider: View {
    @ObservedObject var track: StemTrack

    var body: some View {
        PillSlider(
            title: track.kind.displayName,
            value: $track.volume,
            range: 0...1.5,
            defaultValue: 1,
            isDisabled: track.muted,
            format: { "\(Int(($0 * 100).rounded())) %" }
        )
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryInk)
            .padding(.leading, 4)
    }
}
