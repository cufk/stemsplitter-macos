import AppKit
import SwiftUI

/// Formspråk: ljus neutral bakgrund, vita kort, svart och orange som accenter.
/// Alla färger har en mörk variant som följer systemets utseende.
enum Theme {
    static let accent = Color(red: 0.93, green: 0.33, blue: 0.16)
    static let background = dynamic(light: NSColor(white: 0.925, alpha: 1), dark: NSColor(white: 0.11, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 0.17, alpha: 1))
    static let subtle = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.22, alpha: 1))
    static let fill = dynamic(light: NSColor(white: 0.885, alpha: 1), dark: NSColor(white: 0.30, alpha: 1))
    static let ink = dynamic(light: NSColor(white: 0.08, alpha: 1), dark: NSColor(white: 0.95, alpha: 1))
    static let inkInverse = dynamic(light: .white, dark: NSColor(white: 0.08, alpha: 1))
    static let secondaryInk = dynamic(light: NSColor(white: 0.45, alpha: 1), dark: NSColor(white: 0.62, alpha: 1))
    static let soloLane = dynamic(
        light: NSColor(red: 0.98, green: 0.80, blue: 0.74, alpha: 1),
        dark: NSColor(red: 0.45, green: 0.20, blue: 0.13, alpha: 1)
    )

    static let cornerRadius: CGFloat = 14
    static let shadow = Color.black.opacity(0.06)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    /// Vitt kort med mjuk skugga.
    func card(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.shadow, radius: 8, y: 2)
        )
    }
}
