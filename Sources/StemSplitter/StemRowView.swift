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
                .frame(width: 12, height: 12)
            Text(track.kind.displayName)
                .frame(width: 70, alignment: .leading)
            WaveformView(peaks: track.waveform, color: track.kind.color, progress: progress)
                .frame(height: 32)
                .opacity(track.muted ? 0.3 : 1)
            Slider(value: $track.volume, in: 0...1.5) {
                Text("Volym \(track.kind.displayName)")
            }
            .frame(width: 160)
            .disabled(track.muted)
            .onChange(of: track.volume) { _, newValue in
                onVolumeChanged(track.kind, newValue, track.muted)
            }
            Text("\(Int(track.volume * 100)) %")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(track.muted ? .secondary : .primary)
            Button {
                track.muted.toggle()
                onVolumeChanged(track.kind, track.volume, track.muted)
            } label: {
                Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)
            .help(track.muted ? "Slå på ljudet för \(track.kind.displayName)" : "Stäng av ljudet för \(track.kind.displayName)")
        }
        .padding(.vertical, 4)
    }
}
