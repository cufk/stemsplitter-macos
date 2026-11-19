import SwiftUI
import UniformTypeIdentifiers
import StemSplitterCore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(viewModel: viewModel, playback: viewModel.playback)
                .padding(.horizontal, 28)
                .padding(.top, 34)   // plats för fönsterknapparna (dold titelrad)
                .padding(.bottom, 14)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            // En låt öppnas direkt; flera låtar eller mappar läggs i kön
            viewModel.open(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .alert("Python 3.9–3.12 saknas", isPresented: $viewModel.showPythonInstallPrompt) {
            Button("Ladda ner och installera") { viewModel.installPython() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("StemSplitter behöver Python för att köra AI-separeringen lokalt. Vill du ladda ner den officiella Python 3.12-installationen från python.org (ca 45 MB)? Du installerar paketet i Installer och öppnar sedan filen igen.")
        }
        .alert(
            "StemSplitter",
            isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { if !$0 { viewModel.alertMessage = nil } }),
            presenting: viewModel.alertMessage
        ) { _ in
            Button("OK") { viewModel.alertMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            IdleView(viewModel: viewModel, batch: viewModel.batch, isTargeted: isTargeted)
        case .working:
            WorkingView(
                title: viewModel.title,
                stages: viewModel.stages,
                stage: viewModel.stage,
                status: viewModel.statusMessage,
                progress: viewModel.progressFraction,
                startedAt: viewModel.workStartedAt,
                onCancel: viewModel.cancelWork,
                onShowLog: viewModel.revealLog
            )
        case .failed(let message):
            FailureView(message: message, onRetry: viewModel.retry, onOpen: viewModel.openFileDialog, onShowLog: viewModel.revealLog)
        case .ready:
            PlayerScreen(viewModel: viewModel, isTargeted: isTargeted)
        }
    }
}

private struct PlayerScreen: View {
    @ObservedObject var viewModel: AppViewModel
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(viewModel: viewModel, playback: viewModel.playback)
                .frame(maxHeight: .infinity)
            ExportStatus(viewModel: viewModel)
            TransportPill(viewModel: viewModel, playback: viewModel.playback)
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
        .padding(.bottom, 24)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
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
                .padding(.vertical, 9)
                .card()
            } else if let url = viewModel.exportedURL {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
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
                .padding(.vertical, 9)
                .card()
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.isExporting)
        .animation(.spring(duration: 0.3), value: viewModel.exportedURL)
    }
}

/// Startläget: tomt fönster att dra in låtar i, eller kön om den har låtar.
private struct IdleView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var batch: BatchProcessor
    let isTargeted: Bool

    var body: some View {
        if batch.hasItems {
            QueuePanel(viewModel: viewModel, batch: batch)
                .card(cornerRadius: 22)
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    }
                }
        } else {
            EmptyStateView(isTargeted: isTargeted, onOpen: viewModel.openFileDialog)
        }
    }
}
