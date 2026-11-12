import SwiftUI

struct WaveformView: View {
    let peaks: [Float]
    let color: Color
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let count = max(1, peaks.count)
            let barWidth = max(1, width / CGFloat(count))
            Path { path in
                for (index, peak) in peaks.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let barHeight = max(1, CGFloat(peak) * height)
                    path.addRect(CGRect(
                        x: x,
                        y: (height - barHeight) / 2,
                        width: barWidth * 0.8,
                        height: barHeight
                    ))
                }
            }
            .fill(color.opacity(0.7))
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: width * CGFloat(min(max(progress, 0), 1)))
        }
    }
}
