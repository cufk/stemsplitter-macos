import SwiftUI

/// Tidigare separerade låtar (cachen) — öppnas direkt utan ny separering.
struct LibrarySidebar: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var pendingDelete: ProjectSummary?

    var body: some View {
        List(selection: selection) {
            Section("Bibliotek") {
                if viewModel.library.isEmpty {
                    Text("Separerade låtar hamnar här.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(viewModel.library) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .lineLimit(1)
                        Text(project.createdAt, format: .dateTime.day().month().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(project.id)
                    .contextMenu {
                        Button("Visa i Finder") { viewModel.revealProject(project.id) }
                        Divider()
                        Button("Ta bort…", role: .destructive) { pendingDelete = project }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "internaldrive")
                Text(ByteCountFormatter.string(fromByteCount: viewModel.cacheSize, countStyle: .file))
                    .monospacedDigit()
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .confirmationDialog(
            "Ta bort \(pendingDelete?.name ?? "låten")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { project in
            Button("Ta bort", role: .destructive) { viewModel.deleteProject(project.id) }
        } message: { _ in
            Text("Stems och vågformer tas bort från cachen. Originalfilen påverkas inte.")
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { viewModel.currentProjectKey },
            set: { key in
                if let key { viewModel.selectProject(key) }
            }
        )
    }
}
