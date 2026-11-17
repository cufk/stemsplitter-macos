import SwiftUI
import StemSplitterCore

/// Transportfältet längst ned: tid, loop, hopp, stor svart play-knapp och klick.
struct TransportPill: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        HStack(spacing: 18) {
            TimeLabel(playhead: playback.playhead)
                .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)

            TransportToggle(systemName: "repeat", isOn: $playback.isLooping, help: "Loopa låten (⌘L)")

            TransportButton(systemName: "backward.end.fill", help: "Hoppa bakåt 5 s (⌘←)") {
                playback.skip(by: -5)
            }

            Button {
                playback.togglePlay()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.inkInverse)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.ink))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(playback.isPlaying ? "Paus (mellanslag)" : "Spela (mellanslag)")

            TransportButton(systemName: "forward.end.fill", help: "Hoppa framåt 5 s (⌘→)") {
                playback.skip(by: 5)
            }

            TransportToggle(systemName: "metronome", isOn: $playback.clickEnabled,
                            help: playback.beatGrid == nil ? "Klick (väntar på tempoanalys)" : "Klick i takt med låten (⌘K)")
                .disabled(playback.beatGrid == nil)

            Spacer(minLength: 0)

            Text(TimeFormat.format(playback.duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(height: 70)
        .card(cornerRadius: 22)
    }
}

private struct TimeLabel: View {
    @ObservedObject var playhead: Playhead

    var body: some View {
        Text(TimeFormat.format(playhead.position))
            .font(.callout.monospacedDigit())
            .foregroundStyle(Theme.ink)
    }
}

private struct TransportButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct TransportToggle: View {
    let systemName: String
    @Binding var isOn: Bool
    let help: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Theme.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(isOn ? Theme.accent : Theme.subtle))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
