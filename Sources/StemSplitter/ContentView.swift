import SwiftUI
import UniformTypeIdentifiers
import StemSplitterCore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isTargeted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { AmbientBackground() }
                .navigationTitle(viewModel.title ?? "StemSplitter")
                .navigationSubtitle(subtitle)
                .toolbar { toolbarContent }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { AudioFileSupport.isSupported($0) }) ?? urls.first else { return false }
            viewModel.open(url)
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
    private var detail: some View {
        switch viewModel.phase {
        case .idle:
            EmptyStateView(isTargeted: isTargeted, onOpen: viewModel.openFileDialog)
        case .working:
            WorkingView(
                title: viewModel.title,
                status: viewModel.statusMessage,
                progress: viewModel.progressFraction,
                onCancel: viewModel.cancelWork
            )
        case .ready:
            PlayerView(viewModel: viewModel, playback: viewModel.playback)
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
        case .failed(let message):
            FailureView(message: message, onRetry: viewModel.retry, onOpen: viewModel.openFileDialog)
        }
    }

    private var subtitle: String {
        switch viewModel.phase {
        case .idle: return "Lokal stem-separering"
        case .working: return "Arbetar…"
        case .ready: return "Sång · Trummor · Bas · Övrigt"
        case .failed: return "Fel"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.openFileDialog()
            } label: {
                Label("Öppna ljudfil", systemImage: "plus")
            }
            .help("Öppna ljudfil (⌘O)")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Återställ mixen") { viewModel.resetMix() }
                Button("Återställ tonläge och tempo") { viewModel.playback.resetTuning() }
            } label: {
                Label("Mix", systemImage: "slider.horizontal.3")
            }
            .disabled(!viewModel.isReady)
            .help("Återställ volymer, mute och solo")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.exportMix()
            } label: {
                Label("Exportera mix", systemImage: "square.and.arrow.up")
            }
            .disabled(!viewModel.isReady || viewModel.isExporting)
            .help("Exportera mixen som WAV (⌘E)")
        }
    }
}
