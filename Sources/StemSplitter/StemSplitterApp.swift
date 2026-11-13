import AppKit
import SwiftUI

@main
struct StemSplitterApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        if let url = Bundle.module.url(forResource: "appicon", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            // Dock visar applicationIconImage när appen körs — klipp till rundade hörn
            NSApplication.shared.applicationIconImage = Self.rounded(image, cornerFraction: 0.22)
        }
    }

    private static func rounded(_ image: NSImage, cornerFraction: CGFloat) -> NSImage {
        let size = image.size
        let output = NSImage(size: size)
        output.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSBezierPath(
            roundedRect: rect,
            xRadius: size.width * cornerFraction,
            yRadius: size.height * cornerFraction
        ).addClip()
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        return output
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, playback: viewModel.playback)
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}
