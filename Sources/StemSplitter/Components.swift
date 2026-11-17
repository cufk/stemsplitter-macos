import SwiftUI

/// Rund vit knapp med symbol (som tillbaka- och mer-knapparna i förlagan).
struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 38
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIconLabel(systemName: systemName, size: size)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct CircleIconLabel: View {
    let systemName: String
    var size: CGFloat = 38
    var isActive = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : Theme.ink)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isActive ? Theme.accent : Theme.card)
                    .shadow(color: Theme.shadow, radius: 6, y: 2)
            )
            .contentShape(Circle())
    }
}

/// Smalt reglage: tunn bana, fylld del i given färg och en liten knopp. Dra eller klicka.
struct MiniSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tint: Color = Theme.accent
    var step: Double?
    var defaultValue: Double?
    var accessibilityTitle: String
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded())) %" }
    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let x = width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill).frame(height: 4)
                Capsule().fill(isEnabled ? tint : Theme.secondaryInk).frame(width: max(4, x), height: 4)
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().strokeBorder(isEnabled ? tint : Theme.secondaryInk, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: Theme.shadow, radius: 2, y: 1)
                    .offset(x: min(max(0, x - 6), width - 12))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard isEnabled, width > 0 else { return }
                    update(fraction: drag.location.x / width)
                }
            )
        }
        .frame(height: 16)
        .contextMenu {
            if let defaultValue {
                Button("Återställ") { value = defaultValue }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let increment = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + increment)
            case .decrement: value = max(range.lowerBound, value - increment)
            @unknown default: break
            }
        }
    }

    private func update(fraction: CGFloat) {
        let clamped = Double(min(max(fraction, 0), 1))
        var newValue = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        if let step {
            newValue = (newValue / step).rounded() * step
        }
        value = min(max(newValue, range.lowerBound), range.upperBound)
    }
}

/// Kompakt knapp med rubrik och värde ("TEMPO 98 BPM") som öppnar en liten panel.
struct ValueChip<Panel: View>: View {
    let title: String
    let value: String
    var isHighlighted = false
    var help: String = ""
    @ViewBuilder let panel: () -> Panel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(isHighlighted ? Theme.accent : Theme.secondaryInk)
                Text(value)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? Theme.soloLane.opacity(0.6) : Theme.subtle)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            panel()
                .padding(16)
                .frame(width: 260)
        }
    }
}

/// Liten knapp för mute (M) och solo (S).
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    let onColor: Color
    let help: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.caption2.weight(.bold))
                .frame(width: 22, height: 18)
                .foregroundStyle(isOn ? Color.white : Theme.secondaryInk)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? onColor : Theme.subtle)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
