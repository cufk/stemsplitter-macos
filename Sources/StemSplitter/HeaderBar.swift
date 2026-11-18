import SwiftUI

/// Sidhuvud: tidigare låtar (diskret knapp), titel med tempo, och en meny med övriga val.
struct HeaderBar: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine
    @State private var showLibrary = false

    var body: some View {
        HStack {
            Button {
                showLibrary.toggle()
            } label: {
                CircleIconLabel(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .help("Tidigare låtar")
            .popover(isPresented: $showLibrary, arrowEdge: .bottom) {
                LibraryPopover(viewModel: viewModel) { showLibrary = false }
            }

            CircleIconButton(systemName: "plus", help: "Öppna ljudfil (⌘O)") {
                viewModel.openFileDialog()
            }

            Spacer()

            VStack(spacing: 3) {
                Text(viewModel.title ?? "StemSplitter")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .monospacedDigit()
            }
            .frame(maxWidth: 420)

            Spacer()

            Menu {
                Button("Öppna ljudfil…") { viewModel.openFileDialog() }
                Button("Exportera mix…") { viewModel.exportMix() }
                    .disabled(!viewModel.isReady || viewModel.isExporting)
                Divider()
                Section("Tempo") {
                    Button("Halvera tempot") { viewModel.halveTempo() }
                    Button("Dubbla tempot") { viewModel.doubleTempo() }
                    Button("Flytta ettan ett slag") { viewModel.shiftDownbeat() }
                    Button("Analysera tempot igen") { viewModel.reanalyzeTempo() }
                }
                .disabled(!viewModel.isReady || playback.beatGrid == nil)
                Divider()
                Button("Separera om låten…") { viewModel.reseparateCurrent() }
                    .disabled(!viewModel.isReady)
                Button("Återställ mixen") { viewModel.resetMix() }
                    .disabled(!viewModel.isReady)
                Button("Återställ tempo och tonläge") { playback.resetTuning() }
                    .disabled(!viewModel.isReady)
                Divider()
                Button("Visa logg") { viewModel.revealLog() }
            } label: {
                CircleIconLabel(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Fler val")
        }
    }

    private var subtitle: String {
        switch viewModel.phase {
        case .idle: return "Lokal stem-separering"
        case .working: return "Arbetar…"
        case .failed: return "Något gick fel"
        case .ready:
            if let model = viewModel.currentModelTitle {
                return "\(viewModel.tempoDescription) · \(model)"
            }
            return viewModel.tempoDescription
        }
    }
}

/// Tidigare separerade låtar — dold bakom en knapp i sidhuvudet.
struct LibraryPopover: View {
    @ObservedObject var viewModel: AppViewModel
    let dismiss: () -> Void
    @State private var pendingDelete: ProjectSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tidigare låtar").font(.headline)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: viewModel.cacheSize, countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if viewModel.library.isEmpty {
                Text("Låtar du separerar sparas här och öppnas direkt nästa gång.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(viewModel.library) { project in
                        Button {
                            viewModel.selectProject(project.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name).lineLimit(1)
                                    Text(project.createdAt, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if project.id == viewModel.currentProjectKey {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Visa i Finder") { viewModel.revealProject(project.id) }
                            Divider()
                            Button("Ta bort…", role: .destructive) { pendingDelete = project }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 320, height: viewModel.library.isEmpty ? nil : 360)
        .confirmationDialog(
            "Ta bort \(pendingDelete?.name ?? "låten")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { project in
            Button("Ta bort", role: .destructive) { viewModel.deleteProject(project.id) }
        } message: { _ in
            Text("Stems, vågformer och tempo tas bort från cachen. Originalfilen påverkas inte.")
        }
        .onAppear { viewModel.refreshLibrary() }
    }
}
