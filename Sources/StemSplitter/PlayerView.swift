import SwiftUI
import StemSplitterCore

struct PlayerView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.stems) { track in
                    StemRow(track: track, anySoloed: viewModel.anySoloed, playback: playback)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.automatic)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                ExportStatus(viewModel: viewModel)
                TransportBar(playback: playback)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

/// Följer track för att kunna dimma vågformen när stemmen inte hörs (mute eller annan solo).
private struct StemRow: View {
    @ObservedObject var track: StemTrack
    let anySoloed: Bool
    let playback: PlaybackEngine

    var body: some View {
        StemRowView(
            track: track,
            playhead: playback.playhead,
            duration: playback.duration,
            isSilenced: track.muted || (anySoloed && !track.soloed),
            onSeek: { playback.seek(to: $0) }
        )
    }
}

private struct ExportStatus: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.isExporting {
                HStack(spacing: 12) {
                    ProgressView(value: viewModel.exportProgress)
                        .frame(width: 160)
                    Text("Exporterar mix… \(Int(viewModel.exportProgress * 100)) %")
                        .font(.callout.monospacedDigit())
                    Button("Avbryt") { viewModel.cancelExport() }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassCard(cornerRadius: 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let url = viewModel.exportedURL {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Sparad: \(url.lastPathComponent)")
                        .font(.callout)
                        .lineLimit(1)
                    Button("Visa i Finder") { viewModel.revealExport() }
                        .buttonStyle(.borderless)
                    Button {
                        viewModel.exportedURL = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Stäng")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassCard(cornerRadius: 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.isExporting)
        .animation(.spring(duration: 0.3), value: viewModel.exportedURL)
    }
}
