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
            let barWidth = max(1.5, width / CGFloat(count) * 0.7)
            let playheadX = width * CGFloat(min(max(progress, 0), 1))

            ZStack(alignment: .leading) {
                Path { path in
                    for (index, peak) in peaks.enumerated() {
                        let x = CGFloat(index) * (width / CGFloat(count))
                        let barHeight = max(2, CGFloat(peak) * (height - 4))
                        path.addRoundedRect(
                            in: CGRect(x: x, y: (height - barHeight) / 2, width: barWidth, height: barHeight),
                            cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                        )
                    }
                }
                .fill(color.opacity(0.75))

                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .offset(x: playheadX - 1)
            }
        }
    }
}
