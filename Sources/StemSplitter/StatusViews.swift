import SwiftUI

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
            Text("Dra in en ljudfil")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Låten delas upp i sång, trummor, bas och övrigt — helt lokalt på din Mac. Tempot analyseras så att du kan öva med klick.")
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
    let status: String
    let progress: Double?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            ProgressBar(fraction: progress)
                .frame(width: 320, height: 6)
            if let progress {
                Text("\(Int(progress * 100)) %")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.secondaryInk)
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 380)
            Button("Avbryt", action: onCancel)
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.subtle))
                .keyboardShortcut(.cancelAction)
        }
        .padding(36)
        .frame(width: 460)
        .card(cornerRadius: 26)
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
        }
        .padding(32)
        .frame(width: 480)
        .card(cornerRadius: 26)
    }
}
