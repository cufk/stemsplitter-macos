import SwiftUI
import StemSplitterCore

struct StemRowView: View {
    @ObservedObject var track: StemTrack
    let progress: Double
    let onVolumeChanged: (StemKind, Double, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(track.kind.color)
                .frame(width: 10, height: 10)
            Text(track.kind.displayName)
                .font(.subheadline.weight(.medium))
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(track.muted ? .secondary : .primary)
            WaveformView(peaks: track.waveform, color: track.kind.color, progress: progress)
                .frame(height: 36)
                .opacity(track.muted ? 0.35 : 1)
            Slider(value: $track.volume, in: 0...1.5) {
                Text("Volym \(track.kind.displayName)")
            }
            .tint(track.kind.color)
            .frame(width: 150)
            .disabled(track.muted)
            .onChange(of: track.volume) { _, newValue in
                onVolumeChanged(track.kind, newValue, track.muted)
            }
            Text("\(Int(track.volume * 100)) %")
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(track.muted ? .secondary : .primary)
            Button {
                track.muted.toggle()
                onVolumeChanged(track.kind, track.volume, track.muted)
            } label: {
                Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body)
                    .foregroundStyle(track.muted ? .white : track.kind.color)
                    .frame(width: 30, height: 30)
                    .background(track.muted ? track.kind.color : Color.secondary.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(track.muted ? "Slå på ljudet för \(track.kind.displayName)" : "Stäng av ljudet för \(track.kind.displayName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
