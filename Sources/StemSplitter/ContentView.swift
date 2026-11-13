import AppKit
import SwiftUI
import UniformTypeIdentifiers
import StemSplitterCore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine
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
        .alert("Python 3.9+ saknas", isPresented: $viewModel.showPythonInstallPrompt) {
            Button("Ladda ner och installera") {
                viewModel.installPython()
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("StemSplitter behöver Python 3.9+ för att köra AI-separationen lokalt. Vill du ladda ner den officiella Python 3.12-installationen från python.org (ca 45 MB)? Du installerar paketet själv i Installer och startar sedan om appen.")
        }
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
            Group {
                if let iconURL = Bundle.module.url(forResource: "appicon", withExtension: "jpg"),
                   let nsImage = NSImage(contentsOf: iconURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "waveform")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
            if case .ready = viewModel.phase {
                Button {
                    viewModel.exportMix()
                } label: {
                    Label("Exportera mix", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isExporting)
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
                    progress: playback.duration > 0
                        ? playback.position / playback.duration
                        : 0
                ) { kind, volume, muted in
                    viewModel.setVolume(kind, volume: volume, muted: muted)
                }
            }
            Spacer()
            exportSection
            transportCard
        }
    }

    private var displayedPosition: Double {
        scrubbing ? scrubValue : playback.position
    }

    private var transportCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(TimeFormat.format(displayedPosition))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(
                    value: $scrubValue,
                    in: 0...max(playback.duration, 0.001),
                    onEditingChanged: { editing in
                        if editing {
                            scrubbing = true
                        } else {
                            playback.seek(to: scrubValue)
                            scrubbing = false
                        }
                    }
                )
                .onChange(of: playback.position) { _, newValue in
                    if !scrubbing {
                        scrubValue = newValue
                    }
                }
                Text(TimeFormat.format(playback.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    playback.isLooping.toggle()
                } label: {
                    Image(systemName: playback.isLooping ? "repeat.circle.fill" : "repeat.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(playback.isLooping ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Loopa låten (bra vid övning)")
            }
            HStack {
                Spacer()
                Button {
                    playback.togglePlay()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(" ", modifiers: [])
                .help(playback.isPlaying ? "Paus (mellanslag)" : "Spela (mellanslag)")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var exportSection: some View {
        HStack(spacing: 12) {
            if viewModel.isExporting {
                ProgressView(value: viewModel.exportProgress)
                    .frame(width: 140)
                Text("Exporterar… \(Int(viewModel.exportProgress * 100)) %")
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
