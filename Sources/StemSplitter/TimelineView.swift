import SwiftUI
import StemSplitterCore

private let rulerHeight: CGFloat = 26
private let headerWidth: CGFloat = 196
private let minimumLaneHeight: CGFloat = 58

/// Stems som färgade spår under en gemensam taktlinjal, med ett spelhuvud genom alla spår.
/// Varje spår har namn, mute/solo och ett smalt volymreglage. Spåren fyller tillgänglig höjd.
/// Klicka eller dra i spåren eller linjalen för att hoppa i låten.
struct TimelineView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        GeometryReader { outer in
            let count = max(1, viewModel.stems.count)
            let laneHeight = max(minimumLaneHeight, (outer.size.height - rulerHeight) / CGFloat(count))
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: rulerHeight)
                    ForEach(viewModel.stems) { track in
                        LaneHeader(track: track)
                            .frame(height: laneHeight)
                    }
                }
                .frame(width: headerWidth)

                GeometryReader { geometry in
                    let width = geometry.size.width
                    VStack(spacing: 0) {
                        BarRuler(grid: playback.beatGrid, duration: playback.duration)
                            .frame(height: rulerHeight)
                        VStack(spacing: 0) {
                            ForEach(viewModel.stems) { track in
                                Lane(
                                    track: track,
                                    anySoloed: viewModel.anySoloed,
                                    playhead: playback.playhead,
                                    duration: playback.duration
                                )
                                .frame(height: laneHeight)
                            }
                        }
                        .background(Theme.card)
                        .overlay {
                            BarLines(grid: playback.beatGrid, duration: playback.duration)
                                .allowsHitTesting(false)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Theme.shadow, radius: 8, y: 2)
                    }
                    .overlay(alignment: .topLeading) {
                        PlayheadLine(playhead: playback.playhead, duration: playback.duration, width: width)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onEnded { value in
                            guard width > 0, playback.duration > 0 else { return }
                            playback.seek(to: Double(min(max(value.location.x / width, 0), 1)) * playback.duration)
                        }
                    )
                }
            }
        }
        .frame(minHeight: rulerHeight + minimumLaneHeight * CGFloat(max(1, viewModel.stems.count)))
    }
}

private struct LaneHeader: View {
    @ObservedObject var track: StemTrack

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: track.kind.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(track.muted ? Theme.secondaryInk : Color.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(track.muted ? Theme.subtle : track.kind.color))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(track.kind.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(track.muted ? Theme.secondaryInk : Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ToggleChip(title: "M", isOn: $track.muted, onColor: Theme.ink,
                               help: track.muted ? "Slå på \(track.kind.displayName)" : "Tysta \(track.kind.displayName)")
                    ToggleChip(title: "S", isOn: $track.soloed, onColor: track.kind.color,
                               help: track.soloed ? "Avsluta solo" : "Lyssna bara på \(track.kind.displayName)")
                }
                HStack(spacing: 8) {
                    MiniSlider(
                        value: $track.volume,
                        range: 0...1.5,
                        tint: track.kind.color,
                        defaultValue: 1,
                        accessibilityTitle: "Volym \(track.kind.displayName)"
                    )
                    .disabled(track.muted)
                    Text("\(Int((track.volume * 100).rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(.trailing, 2)
    }
}

private struct Lane: View {
    @ObservedObject var track: StemTrack
    let anySoloed: Bool
    let playhead: Playhead
    let duration: TimeInterval

    var body: some View {
        let silenced = track.muted || (anySoloed && !track.soloed)
        let color = silenced ? Theme.secondaryInk : track.kind.color
        ZStack {
            Rectangle().fill(track.kind.color.opacity(track.soloed ? 0.16 : 0.05))
            if track.waveform.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                PlayedWaveform(peaks: track.waveform, color: color, playhead: playhead, duration: duration)
                    .padding(.vertical, 10)
                    .opacity(silenced ? 0.4 : 1)
            }
            Rectangle()
                .fill(Theme.ink.opacity(0.05))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.easeInOut(duration: 0.15), value: track.soloed)
        .animation(.easeInOut(duration: 0.15), value: silenced)
    }
}

/// Vågform där den spelade delen har full färg och resten är dämpad.
/// Bara masken följer spelhuvudet; själva vågformerna ritas inte om.
private struct PlayedWaveform: View {
    let peaks: [Float]
    let color: Color
    @ObservedObject var playhead: Playhead
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            let fraction = duration > 0 ? min(max(playhead.position / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                WaveformView(peaks: peaks, color: color.opacity(0.35)).equatable()
                WaveformView(peaks: peaks, color: color).equatable()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geometry.size.width * fraction)
                    }
            }
        }
    }
}

/// Taktnummer ovanför spåren (glesare när låten är lång). Utan tempo: tidsmarkeringar.
private struct BarRuler: View {
    let grid: BeatGrid?
    let duration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            let font = Font.caption2.monospacedDigit()
            if let grid, !grid.barStarts.isEmpty {
                let bars = grid.barStarts
                let averageBar = bars.count > 1 ? (bars.last! - bars.first!) / Double(bars.count - 1) : duration
                let pixelsPerBar = size.width * averageBar / duration
                let every = labelStride(pixelsPerItem: pixelsPerBar, minimumSpacing: 34)
                for (index, time) in bars.enumerated() where index % every == 0 {
                    let x = size.width * time / duration
                    context.draw(Text("\(index + 1)").font(font).foregroundStyle(Theme.secondaryInk),
                                 at: CGPoint(x: x, y: size.height / 2), anchor: .center)
                }
            } else {
                let candidates: [Double] = [5, 10, 15, 30, 60, 120]
                let interval = candidates.first { size.width * $0 / duration >= 50 } ?? 300
                var time = 0.0
                while time <= duration {
                    let x = size.width * time / duration
                    context.draw(Text(TimeFormat.format(time)).font(font).foregroundStyle(Theme.secondaryInk),
                                 at: CGPoint(x: x, y: size.height / 2), anchor: time == 0 ? .leading : .center)
                    time += interval
                }
            }
        }
    }
}

/// Svaga lodräta linjer vid varje takt (eller grupp av takter).
private struct BarLines: View {
    let grid: BeatGrid?
    let duration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard let grid, duration > 0 else { return }
            let bars = grid.barStarts
            guard bars.count > 1 else { return }
            let averageBar = (bars.last! - bars.first!) / Double(bars.count - 1)
            let every = labelStride(pixelsPerItem: size.width * averageBar / duration, minimumSpacing: 34)
            var path = Path()
            for (index, time) in bars.enumerated() where index % every == 0 {
                let x = size.width * time / duration
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(Theme.ink.opacity(0.08)), lineWidth: 1)
        }
    }
}

/// 1, 2, 4, 8 … takter mellan etiketter så att de inte krockar.
private func labelStride(pixelsPerItem: CGFloat, minimumSpacing: CGFloat) -> Int {
    guard pixelsPerItem > 0 else { return 1 }
    var stride = 1
    while CGFloat(stride) * pixelsPerItem < minimumSpacing && stride < 1024 {
        stride *= 2
    }
    return stride
}

/// Den enda vyn som följer uppspelningspositionen (~30 gånger per sekund).
private struct PlayheadLine: View {
    @ObservedObject var playhead: Playhead
    let duration: TimeInterval
    let width: CGFloat

    var body: some View {
        let fraction = duration > 0 ? min(max(playhead.position / duration, 0), 1) : 0
        let x = width * fraction
        VStack(spacing: 0) {
            Circle()
                .fill(Theme.ink)
                .frame(width: 7, height: 7)
                .padding(.top, rulerHeight - 9)
            Rectangle()
                .fill(Theme.ink)
                .frame(width: 1.5)
        }
        .frame(width: 8)
        .offset(x: x - 4)
    }
}
