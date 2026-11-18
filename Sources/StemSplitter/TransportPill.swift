import SwiftUI
import StemSplitterCore

/// Transportfältet längst ned: tid till vänster, uppspelning i mitten, övning (tempo, tonläge, klick) till höger.
struct TransportPill: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        HStack(spacing: 12) {
            TimeReadout(playhead: playback.playhead, duration: playback.duration)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                TransportToggle(systemName: "repeat", isOn: $playback.isLooping, help: "Loopa låten (⌘L)")
                TransportButton(systemName: "gobackward.5", help: "Hoppa bakåt 5 s (⌘←)") {
                    playback.skip(by: -5)
                }
                Button {
                    playback.togglePlay()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.inkInverse)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Theme.ink))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(playback.isPlaying ? "Paus (mellanslag)" : "Spela (mellanslag)")
                TransportButton(systemName: "goforward.5", help: "Hoppa framåt 5 s (⌘→)") {
                    playback.skip(by: 5)
                }
                TransportToggle(systemName: "metronome", isOn: $playback.clickEnabled,
                                help: playback.beatGrid == nil ? "Klick (väntar på tempoanalys)" : "Klick i takt med låten (⌘K)")
                    .disabled(playback.beatGrid == nil)
            }

            HStack(spacing: 8) {
                TempoChip(playback: playback)
                PitchChip(playback: playback)
                ClickChip(viewModel: viewModel, playback: playback)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .card(cornerRadius: 20)
    }
}

private struct TimeReadout: View {
    @ObservedObject var playhead: Playhead
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Text(TimeFormat.format(playhead.position))
                .foregroundStyle(Theme.ink)
            Text("/ \(TimeFormat.format(duration))")
                .foregroundStyle(Theme.secondaryInk)
        }
        .font(.callout.monospacedDigit())
    }
}

// MARK: - Övningsknappar

private struct TempoChip: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        ValueChip(title: "Tempo", value: value, isHighlighted: playback.tempo != 1, help: "Ändra tempo utan att ändra tonläge") {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Tempo", value: value)
                MiniSlider(value: $playback.tempo, range: 0.5...2.0, step: 0.05, defaultValue: 1,
                           accessibilityTitle: "Tempo")
                HStack(spacing: 6) {
                    ForEach([0.5, 0.75, 0.9, 1.0], id: \.self) { preset in
                        PresetButton(title: "\(Int(preset * 100)) %", isSelected: abs(playback.tempo - preset) < 0.001) {
                            playback.tempo = preset
                        }
                    }
                }
                Text("Tonläget ändras inte.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    private var value: String {
        let percent = "\(Int((playback.tempo * 100).rounded())) %"
        guard let bpm = playback.beatGrid?.bpm else { return percent }
        return "\(Int((bpm * playback.tempo).rounded())) BPM"
    }
}

private struct PitchChip: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        ValueChip(title: "Tonläge", value: value, isHighlighted: playback.pitchSemitones != 0, help: "Ändra tonläge utan att ändra tempo") {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Tonläge", value: value)
                HStack(spacing: 10) {
                    StepButton(systemName: "minus") {
                        playback.pitchSemitones = max(-12, playback.pitchSemitones - 1)
                    }
                    MiniSlider(value: $playback.pitchSemitones, range: -12...12, step: 1, defaultValue: 0,
                               accessibilityTitle: "Tonläge", format: { "\(Int($0)) halvtoner" })
                    StepButton(systemName: "plus") {
                        playback.pitchSemitones = min(12, playback.pitchSemitones + 1)
                    }
                }
                HStack {
                    Text("Tempot ändras inte.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    if playback.pitchSemitones != 0 {
                        PresetButton(title: "Återställ", isSelected: false) { playback.pitchSemitones = 0 }
                    }
                }
            }
        }
    }

    private var value: String {
        let semitones = Int(playback.pitchSemitones.rounded())
        return semitones > 0 ? "+\(semitones) st" : "\(semitones) st"
    }
}

private struct ClickChip: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        ValueChip(title: "Klick", value: value, isHighlighted: playback.clickEnabled, help: "Klickvolym och tempoinställningar") {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Klick", value: viewModel.tempoDescription)
                Toggle("Klick i takt med låten", isOn: $playback.clickEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(playback.beatGrid == nil)
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.1.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                    MiniSlider(value: $playback.clickVolume, range: 0...1, defaultValue: 0.7,
                               accessibilityTitle: "Klickvolym")
                }
                .disabled(playback.beatGrid == nil)
                Divider()
                Text("Stämmer inte tempot?")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                HStack(spacing: 6) {
                    PresetButton(title: "½ tempo", isSelected: false) { viewModel.halveTempo() }
                    PresetButton(title: "2× tempo", isSelected: false) { viewModel.doubleTempo() }
                    PresetButton(title: "Flytta 1:an", isSelected: false) { viewModel.shiftDownbeat() }
                }
                .disabled(playback.beatGrid == nil)
            }
        }
    }

    private var value: String {
        guard playback.beatGrid != nil else { return viewModel.isAnalyzingTempo ? "Analyserar" : "–" }
        return playback.clickEnabled ? "\(Int((playback.clickVolume * 100).rounded())) %" : "Av"
    }
}

private struct PanelHeader: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.secondaryInk)
        }
    }
}

private struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Theme.accent : Theme.subtle))
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

private struct StepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.subtle))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transportknappar

private struct TransportButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Theme.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? Theme.accent : Theme.subtle))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
