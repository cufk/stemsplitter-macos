import SwiftUI

struct EmptyStateView: View {
    let isTargeted: Bool
    let onOpen: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Dra in en ljudfil", systemImage: "waveform.badge.plus")
        } description: {
            Text("Låten delas upp i sång, trummor, bas och övrigt — helt lokalt på din Mac.\nWAV, AIFF, CAF, MP3, M4A, AAC och FLAC stöds.")
        } actions: {
            Button("Öppna ljudfil…", action: onOpen)
                .glassButton(prominent: true)
                .controlSize(.large)
        }
        .padding(40)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
        }
        .frame(maxWidth: 560)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .padding(32)
    }
}

struct WorkingView: View {
    let title: String?
    let status: String
    let progress: Double?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: true)
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 320)
                Text("\(Int(progress * 100)) %")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 320)
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 380)
            Button("Avbryt", role: .cancel, action: onCancel)
                .glassButton()
                .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(width: 460)
        .glassCard(cornerRadius: 28)
    }
}

struct FailureView: View {
    let message: String
    let onRetry: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Något gick fel", systemImage: "exclamationmark.triangle")
        } description: {
            ScrollView {
                Text(message)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 160)
        } actions: {
            HStack {
                Button("Försök igen", action: onRetry)
                    .glassButton(prominent: true)
                Button("Öppna annan fil…", action: onOpen)
                    .glassButton()
            }
        }
        .frame(maxWidth: 560)
    }
}
