import SwiftUI

/// Liquid Glass på macOS 26 (byggt med Xcode 26+), material-reservläge annars.
extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    @ViewBuilder
    func glassCircle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(.regularMaterial, in: Circle())
        }
        #else
        self.background(.regularMaterial, in: Circle())
        #endif
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
        #else
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
        #endif
    }
}

/// Grupperar glaselement så att de smälter ihop på macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Diskret färgbakgrund i stemfärgerna — ger glaset något att bryta ljuset mot.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Circle().fill(Color.pink.opacity(0.18))
                        .frame(width: size.width * 0.6)
                        .position(x: size.width * 0.15, y: size.height * 0.2)
                    Circle().fill(Color.purple.opacity(0.16))
                        .frame(width: size.width * 0.55)
                        .position(x: size.width * 0.9, y: size.height * 0.35)
                    Circle().fill(Color.teal.opacity(0.14))
                        .frame(width: size.width * 0.5)
                        .position(x: size.width * 0.45, y: size.height * 1.0)
                }
                .blur(radius: 90)
            }
        }
        .ignoresSafeArea()
    }
}
