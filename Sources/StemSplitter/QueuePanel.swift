import SwiftUI
import StemSplitterCore

/// Kön: varje låts status, samlat förlopp och knappar för att avbryta, rensa och öppna.
struct QueuePanel: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var batch: BatchProcessor

    var body: some View {
        let queue = batch.queue
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Kö").font(.headline)
                    Spacer()
                    Text("\(queue.finishedCount) av \(queue.counted.count) klara")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                }
                QueueProgressBar(fraction: queue.overallProgress)
                    .frame(height: 5)
                if batch.isPaused {
                    Text("Kön väntar på Python. Installera Python 3.12 och tryck sedan på Fortsätt.")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(queue.items) { item in
                        QueueRow(item: item,
                                 onCancel: { batch.cancel(item.id) },
                                 onRemove: { batch.remove(item.id) },
                                 onOpen: { viewModel.openQueued(item) })
                        if item.id != queue.items.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
            .frame(maxHeight: 340)

            Divider()

            HStack(spacing: 10) {
                Button("Lägg till låtar…") { viewModel.openFileDialog() }
                Spacer()
                if queue.items.contains(where: { $0.state.isFinished }) {
                    Button("Rensa klara") { batch.clearFinished() }
                }
                if batch.isPaused {
                    Button("Fortsätt") { batch.resume() }
                } else if batch.isActive {
                    Button("Avbryt alla", role: .destructive) { batch.cancelAll() }
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420)
    }
}

private struct QueueRow: View {
    let item: BatchItem
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isFailure ? Theme.accent : Theme.secondaryInk)
                    .lineLimit(2)
                if case .working(let stage, let progress) = item.state {
                    QueueProgressBar(fraction: BatchQueue.itemProgress(stage: stage, progress: progress))
                        .frame(height: 3)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item.state.projectKey != nil { onOpen() } }
    }

    private var isFailure: Bool {
        if case .failed = item.state { return true }
        return false
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.state {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(Theme.secondaryInk)
        case .working:
            ProgressView().controlSize(.small)
        case .done, .alreadyInLibrary:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(Theme.secondaryInk)
        }
    }

    private var statusText: String {
        switch item.state {
        case .waiting: return "Väntar"
        case .working(let stage, let progress):
            let percent = progress.map { " \(Int(($0 * 100).rounded(.down))) %" } ?? ""
            return stage.title + percent
        case .done: return "Klar"
        case .alreadyInLibrary: return "Fanns redan i biblioteket"
        case .failed(let message): return message
        case .cancelled: return "Avbruten"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.state {
        case .waiting, .working:
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.subtle))
            }
            .buttonStyle(.plain)
            .help("Avbryt den här låten")
        case .done, .alreadyInLibrary:
            Button("Öppna", action: onOpen)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkInverse)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.ink))
        case .failed, .cancelled:
            Button(action: onRemove) {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Ta bort ur listan")
        }
    }
}

struct QueueProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtle)
                Capsule().fill(Theme.accent)
                    .frame(width: geometry.size.width * CGFloat(min(max(fraction, 0), 1)))
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
    }
}

/// Knapp i sidhuvudet: ring med köns förlopp och antal låtar kvar.
struct QueueButtonLabel: View {
    @ObservedObject var batch: BatchProcessor

    var body: some View {
        let queue = batch.queue
        let remaining = queue.counted.count - queue.finishedCount
        ZStack {
            Circle().fill(Theme.card).shadow(color: Theme.shadow, radius: 6, y: 2)
            Circle()
                .trim(from: 0, to: CGFloat(queue.overallProgress))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
                .animation(.easeOut(duration: 0.25), value: queue.overallProgress)
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 38, height: 38)
        .contentShape(Circle())
    }
}
