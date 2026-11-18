import SwiftUI
import StemSplitterCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var confirmClear = false
    @AppStorage(SeparationModel.defaultsKey) private var model = SeparationModel.standard.rawValue

    var body: some View {
        Form {
            Section("Separering") {
                Picker("Kvalitet", selection: $model) {
                    ForEach(SeparationModel.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Text(SeparationModel.from(defaultsValue: model).detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Gäller nya låtar. Välj \"Separera om låten\" i menyn … för att göra om en låt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Bibliotek och cache") {
                LabeledContent("Sparade låtar", value: "\(viewModel.library.count)")
                LabeledContent("Använt utrymme") {
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.cacheSize, countStyle: .file))
                        .monospacedDigit()
                }
                HStack {
                    Button("Visa i Finder") { viewModel.revealAppSupport() }
                    Spacer()
                    Button("Töm cache…", role: .destructive) { confirmClear = true }
                        .disabled(viewModel.library.isEmpty)
                }
            }
            Section("Integritet") {
                Text("All separering sker lokalt med Demucs. Ingen ljudfil lämnar din Mac. Internet används bara första gången, för att installera AI-miljön.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { viewModel.refreshLibrary() }
        .confirmationDialog("Töm hela cachen?", isPresented: $confirmClear) {
            Button("Töm cache", role: .destructive) { viewModel.clearCache() }
        } message: {
            Text("Alla separerade låtar tas bort och måste separeras igen. Dina originalfiler påverkas inte.")
        }
    }
}
