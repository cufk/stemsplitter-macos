import SwiftUI

/// Vågform som spegelvända staplar (Canvas). Ritas bara om när topparna eller färgen ändras.
struct WaveformView: View, Equatable {
    let peaks: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0 else { return }
            let step = size.width / CGFloat(peaks.count)
            let barWidth = max(1, step * 0.55)
            let middle = size.height / 2
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let height = max(1, CGFloat(min(peak, 1)) * size.height)
                path.addRect(CGRect(x: CGFloat(index) * step, y: middle - height / 2, width: barWidth, height: height))
            }
            context.fill(path, with: .color(color))
        }
    }

    static func == (lhs: WaveformView, rhs: WaveformView) -> Bool {
        lhs.color == rhs.color && lhs.peaks == rhs.peaks
    }
}
