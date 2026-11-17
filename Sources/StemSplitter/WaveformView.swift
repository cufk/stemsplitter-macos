import SwiftUI

/// Ritar vågformen en gång (Canvas). Ändras bara när topparna eller färgen ändras.
struct WaveformView: View, Equatable {
    let peaks: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0 else { return }
            let step = size.width / CGFloat(peaks.count)
            let barWidth = max(1, step * 0.62)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let height = max(1.5, CGFloat(min(peak, 1)) * (size.height - 2))
                path.addRoundedRect(
                    in: CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: barWidth, height: height),
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
            }
            context.fill(path, with: .color(color))
        }
    }
}

/// Vågform med spelad del i full färg, spelhuvud och klick/dra för att söka.
/// Det är bara den här vyn som följer uppspelningspositionen.
struct StemWaveform: View {
    let peaks: [Float]
    let color: Color
    @ObservedObject var playhead: Playhead
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = duration > 0 ? min(max(playhead.position / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                WaveformView(peaks: peaks, color: color.opacity(0.28)).equatable()
                WaveformView(peaks: peaks, color: color).equatable()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * progress)
                    }
                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 2)
                    .offset(x: width * progress - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    guard width > 0 else { return }
                    onSeek(Double(min(max(value.location.x / width, 0), 1)) * duration)
                }
            )
        }
        .overlay {
            if peaks.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
    }
}

extension WaveformView {
    static func == (lhs: WaveformView, rhs: WaveformView) -> Bool {
        lhs.color == rhs.color && lhs.peaks == rhs.peaks
    }
}
