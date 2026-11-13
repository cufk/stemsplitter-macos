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
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            content
                .padding(20)
        }
        .background(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
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
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(
                        colors: [.pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("StemSplitter")
                    .font(.title3.bold())
                if let inputURL = viewModel.inputURL {
                    Text(inputURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if case .ready = viewModel.phase {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button("Öppna ljudfil…") {
                viewModel.openFileDialog()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
    }

    private var content: some View {
        Group {
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
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Dra en lokal ljudfil hit, eller öppna en med knappen ovanför")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Filen delas upp lokalt i sång, trummor, bas och övrigt — ingen musik lämnar din Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var busyView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                if let fraction = viewModel.progressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 320)
                    Text("\(Int(fraction * 100)) %")
                        .font(.title3.bold().monospacedDigit())
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text("Något gick fel")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Försök igen") {
                if let url = viewModel.inputURL {
                    Task { await viewModel.load(url) }
                }
            }
            .buttonStyle(.borderedProminent)
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
        HStack(spacing: 18) {
            Button {
                viewModel.playback.togglePlay()
            } label: {
                Image(systemName: viewModel.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(" ", modifiers: [])
            .help(viewModel.playback.isPlaying ? "Paus (mellanslag)" : "Spela (mellanslag)")

            Button {
                viewModel.playback.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stoppa")

            Button {
                viewModel.playback.isLooping.toggle()
            } label: {
                Image(systemName: viewModel.playback.isLooping ? "repeat.circle.fill" : "repeat.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(viewModel.playback.isLooping ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Loopa låten (bra vid övning)")

            Spacer()

            Text(TimeFormat.format(displayedPosition))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
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
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var exportSection: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.exportMix()
            } label: {
                Label("Exportera mix", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isExporting || viewModel.stems.isEmpty)
            if viewModel.isExporting {
                ProgressView(value: viewModel.exportProgress)
                    .frame(width: 140)
                Text("\(Int(viewModel.exportProgress * 100)) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let exportedURL = viewModel.exportedURL {
                Label("Sparad: \(exportedURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Text("Exporten använder de volymer och mutes du ställt in just nu (WAV).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
