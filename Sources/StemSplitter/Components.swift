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

/// Brett reglage i form av ett piller: etikett till vänster, värde till höger,
/// fylld del och ett handtag som visar positionen. Dra eller klicka för att ändra.
struct PillSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var defaultValue: Double?
    var isDisabled = false
    let format: (Double) -> String

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let x = width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.subtle)
                    .frame(width: max(x, 0))
                Capsule()
                    .fill(Theme.fill)
                    .frame(width: 2, height: 20)
                    .offset(x: max(0, min(width - 2, x - 1)))
                HStack {
                    Text(title)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(format(value))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryInk)
                }
                .font(.callout)
                .padding(.horizontal, 14)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard !isDisabled, width > 0 else { return }
                    update(fraction: drag.location.x / width)
                }
            )
        }
        .frame(height: 42)
        .shadow(color: Theme.shadow, radius: 6, y: 2)
        .opacity(isDisabled ? 0.45 : 1)
        .contextMenu {
            if let defaultValue {
                Button("Återställ") { value = defaultValue }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
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

/// Bred knapp med kontur i pillerform ("+ Add Track" i förlagan).
struct OutlinePillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.fill, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
