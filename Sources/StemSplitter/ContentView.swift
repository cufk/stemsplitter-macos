import AppKit
import SwiftUI
import UniformTypeIdentifiers
import StemSplitterCore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isTargeted = false
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if case .busy = viewModel.phase {
                busyView
            } else if case .ready = viewModel.phase {
                readyView
            } else if case .failed(let message) = viewModel.phase {
                errorView(message)
            } else {
                idleView
            }
        }
        .padding(16)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL? = {
                    if let url = item as? URL { return url }
                    if let data = item as? Data, let path = String(data: data, encoding: .utf8) {
                        return URL(fileURLWithPath: path)
                    }
                    return nil
                }()
                if let url {
                    Task { await viewModel.load(url) }
                }
            }
            return true
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("StemSplitter")
                .font(.title2.bold())
            Spacer()
            if let inputURL = viewModel.inputURL {
                Text(inputURL.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button("Öppna ljudfil…") {
                viewModel.openFileDialog()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Dra en lokal ljudfil hit, eller öppna en med knappen ovanför.")
                .multilineTextAlignment(.center)
            Text("Filen delas upp lokalt i sång, trummor, bas och övrigt — ingen musik lämnar din Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var busyView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: viewModel.progressFraction ?? 0) {
                Text(viewModel.statusMessage)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if viewModel.progressFraction == nil {
                ProgressView()
            }
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Något gick fel")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Försök igen") {
                if let url = viewModel.inputURL {
                    Task { await viewModel.load(url) }
                }
            }
            Spacer()
        }
    }

    private var readyView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.stems) { track in
                StemRowView(
                    track: track,
                    progress: viewModel.playback.duration > 0
                        ? viewModel.playback.position / viewModel.playback.duration
                        : 0
                ) { kind, volume, muted in
                    viewModel.setVolume(kind, volume: volume, muted: muted)
                }
                Divider()
            }
            transport
            exportSection
            Spacer()
        }
    }

    private var displayedPosition: Double {
        scrubbing ? scrubValue : viewModel.playback.position
    }

    private var transport: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    viewModel.playback.togglePlay()
                } label: {
                    Image(systemName: viewModel.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .help(viewModel.playback.isPlaying ? "Paus" : "Spela")

                Button {
                    viewModel.playback.stop()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .help("Stoppa")

                Button {
                    viewModel.playback.isLooping.toggle()
                } label: {
                    Image(systemName: viewModel.playback.isLooping ? "repeat.circle.fill" : "repeat.circle")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.playback.isLooping ? Color.accentColor : Color.primary)
                .help("Loopa låten (bra vid övning)")

                Spacer()

                Text(TimeFormat.format(displayedPosition))
                    .font(.caption.monospacedDigit())
                Slider(
                    value: $scrubValue,
                    in: 0...max(viewModel.playback.duration, 0.001),
                    onEditingChanged: { editing in
                        if editing {
                            scrubbing = true
                        } else {
                            viewModel.playback.seek(to: scrubValue)
                            scrubbing = false
                        }
                    }
                )
                .onChange(of: viewModel.playback.position) { _, newValue in
                    if !scrubbing {
                        scrubValue = newValue
                    }
                }
                Text(TimeFormat.format(viewModel.playback.duration))
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private var exportSection: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Exportera mix…") {
                    viewModel.exportMix()
                }
                .disabled(viewModel.isExporting || viewModel.stems.isEmpty)
                if viewModel.isExporting {
                    ProgressView(value: viewModel.exportProgress)
                        .frame(width: 160)
                    Text("\(Int(viewModel.exportProgress * 100)) %")
                        .font(.caption)
                }
                if let exportedURL = viewModel.exportedURL {
                    Text("Sparad: \(exportedURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Exporten använder de volymer och mutes du ställt in just nu, och sparas som en WAV-fil.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
