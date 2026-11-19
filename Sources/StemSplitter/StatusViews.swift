import SwiftUI
import StemSplitterCore

struct EmptyStateView: View {
    let isTargeted: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onOpen) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.inkInverse)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(isTargeted ? Theme.accent : Theme.ink))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            Text("Dra in låtar")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("En låt eller flera — eller en hel mapp. Varje låt delas upp i sång, trummor, bas och övrigt, helt lokalt på din Mac. Flera låtar körs efter varandra i en kö.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Text("WAV · AIFF · CAF · MP3 · M4A · AAC · FLAC")
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(44)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isTargeted ? Theme.soloLane.opacity(0.5) : Theme.card)
                .shadow(color: Theme.shadow, radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

struct WorkingView: View {
    let title: String?
    let stages: [WorkStage]
    let stage: WorkStage
    let status: String
    let progress: Double?
    let startedAt: Date?
    let onCancel: () -> Void
    let onShowLog: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                if let startedAt {
                    SwiftUI.TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("Tid: \(TimeFormat.format(context.date.timeIntervalSince(startedAt)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
            }

            // Stora procentsiffror för steget som pågår
            VStack(spacing: 10) {
                Text(progress.map { "\(Int(($0 * 100).rounded(.down))) %" } ?? "—")
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(progress == nil ? Theme.secondaryInk : Theme.ink)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: progress)
                ProgressBar(fraction: progress)
                    .frame(width: 340, height: 6)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(stages, id: \.self) { item in
                    StageRow(title: item.title, state: state(of: item))
                }
            }
            .frame(width: 340, alignment: .leading)

            Text(status)
                .font(.callout)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 380, minHeight: 36, alignment: .top)

            HStack(spacing: 10) {
                Button("Avbryt", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.subtle))
                    .keyboardShortcut(.cancelAction)
                Button("Visa logg", action: onShowLog)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .padding(36)
        .frame(width: 480)
        .card(cornerRadius: 26)
    }

    private func state(of item: WorkStage) -> StageRow.State {
        if item < stage { return .done }
        if item == stage { return .active }
        return .pending
    }
}

private struct StageRow: View {
    enum State { case done, active, pending }
    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                case .active:
                    ProgressView()
                        .controlSize(.small)
                case .pending:
                    Circle()
                        .strokeBorder(Theme.fill, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 18, height: 18)
            Text(title)
                .font(.callout.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .pending ? Theme.secondaryInk : Theme.ink)
        }
    }
}

/// Orange förloppsindikator; utan värde visas en glidande del.
private struct ProgressBar: View {
    let fraction: Double?
    @State private var phase: CGFloat = -0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtle)
                if let fraction {
                    Capsule().fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.2), value: fraction)
                } else {
                    Capsule().fill(Theme.accent)
                        .frame(width: geometry.size.width * 0.3)
                        .offset(x: geometry.size.width * phase)
                        .onAppear {
                            phase = -0.3
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                                phase = 0.7
                            }
                        }
                }
            }
            .clipShape(Capsule())
        }
    }
}

struct FailureView: View {
    let message: String
    let onRetry: () -> Void
    let onOpen: () -> Void
    let onShowLog: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text("Något gick fel")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            ScrollView {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 140)
            HStack(spacing: 10) {
                Button("Försök igen", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.inkInverse)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.ink))
                Button("Öppna annan fil…", action: onOpen)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.subtle))
            }
            Button("Visa logg", action: onShowLog)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(32)
        .frame(width: 480)
        .card(cornerRadius: 26)
    }
}
