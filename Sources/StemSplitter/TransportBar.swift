import SwiftUI
import StemSplitterCore

/// Flytande transportfält längst ned: tidslinje, play/paus, hopp, loop, tonläge och tempo.
struct TransportBar: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        VStack(spacing: 12) {
            TimelineScrubber(playback: playback, playhead: playback.playhead)

            HStack(spacing: 0) {
                TuningControls(playback: playback)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassGroup(spacing: 10) {
                    HStack(spacing: 12) {
                        RoundIconButton(systemName: "gobackward.5", size: 34, help: "Hoppa bakåt 5 s (⌘←)") {
                            playback.skip(by: -5)
                        }
                        Button {
                            playback.togglePlay()
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 30, height: 30)
                        }
                        .glassButton(prominent: true)
                        .buttonBorderShape(.circle)
                        .controlSize(.extraLarge)
                        .keyboardShortcut(.space, modifiers: [])
                        .help(playback.isPlaying ? "Paus (mellanslag)" : "Spela (mellanslag)")
                        RoundIconButton(systemName: "goforward.5", size: 34, help: "Hoppa framåt 5 s (⌘→)") {
                            playback.skip(by: 5)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Toggle(isOn: $playback.isLooping) {
                        Label("Loopa", systemImage: "repeat")
                    }
                    .toggleStyle(.button)
                    .glassButton()
                    .help("Loopa låten (⌘L)")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 26)
    }
}

private struct TimelineScrubber: View {
    @ObservedObject var playback: PlaybackEngine
    @ObservedObject var playhead: Playhead
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Text(TimeFormat.format(scrubbing ? scrubValue : playhead.position))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : playhead.position },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(playback.duration, 0.001),
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = playhead.position
                        scrubbing = true
                    } else {
                        playback.seek(to: scrubValue)
                        scrubbing = false
                    }
                }
            )
            .accessibilityLabel("Position i låten")
            Text(TimeFormat.format(playback.duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
    }
}

private struct TuningControls: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tonläge").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    SmallStepButton(systemName: "minus", help: "Sänk en halvton") {
                        playback.pitchSemitones = max(-12, playback.pitchSemitones - 1)
                    }
                    Text(semitoneLabel)
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 44)
                    SmallStepButton(systemName: "plus", help: "Höj en halvton") {
                        playback.pitchSemitones = min(12, playback.pitchSemitones + 1)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Tempo").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Slider(value: $playback.tempo, in: 0.5...2.0, step: 0.05)
                        .frame(width: 110)
                        .accessibilityLabel("Tempo")
                    Text(String(format: "%.2f×", playback.tempo))
                        .font(.callout.monospacedDigit())
                        .frame(width: 46, alignment: .leading)
                }
            }
            if playback.pitchSemitones != 0 || playback.tempo != 1 {
                Button {
                    playback.resetTuning()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Återställ tonläge och tempo (⌘0)")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: playback.pitchSemitones != 0 || playback.tempo != 1)
    }

    private var semitoneLabel: String {
        let value = Int(playback.pitchSemitones)
        return value > 0 ? "+\(value) st" : "\(value) st"
    }
}

private struct SmallStepButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .background(Color.secondary.opacity(0.14), in: Circle())
        .help(help)
    }
}

struct RoundIconButton: View {
    let systemName: String
    let size: CGFloat
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .help(help)
    }
}
