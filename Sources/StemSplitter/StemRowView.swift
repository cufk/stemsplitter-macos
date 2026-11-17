import SwiftUI
import StemSplitterCore

struct StemRowView: View {
    @ObservedObject var track: StemTrack
    /// Följs inte här — bara vågformen ritas om när positionen ändras.
    let playhead: Playhead
    let duration: TimeInterval
    let isSilenced: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(track.kind.displayName).font(.headline)
                } icon: {
                    Image(systemName: track.kind.symbolName)
                        .foregroundStyle(track.kind.color)
                }
                HStack(spacing: 6) {
                    ToggleChip(title: "M", isOn: $track.muted, tint: .red, foreground: .white,
                               help: track.muted ? "Slå på \(track.kind.displayName)" : "Tysta \(track.kind.displayName)")
                    ToggleChip(title: "S", isOn: $track.soloed, tint: .yellow, foreground: .black,
                               help: track.soloed ? "Avsluta solo" : "Lyssna bara på \(track.kind.displayName)")
                }
            }
            .frame(width: 120, alignment: .leading)

            StemWaveform(
                peaks: track.waveform,
                color: track.kind.color,
                playhead: playhead,
                duration: duration,
                onSeek: onSeek
            )
            .frame(height: 48)
            .opacity(isSilenced ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.2), value: isSilenced)

            VStack(alignment: .trailing, spacing: 2) {
                Slider(value: $track.volume, in: 0...1.5)
                    .tint(track.kind.color)
                    .frame(width: 140)
                    .disabled(track.muted)
                    .accessibilityLabel("Volym \(track.kind.displayName)")
                Text("\(Int((track.volume * 100).rounded())) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 20)
        .contextMenu {
            Button("Återställ volym") { track.volume = 1 }
        }
    }
}

struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color
    let foreground: Color
    let help: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 20)
                .foregroundStyle(isOn ? foreground : Color.secondary)
                .background(
                    isOn ? tint : Color.secondary.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
