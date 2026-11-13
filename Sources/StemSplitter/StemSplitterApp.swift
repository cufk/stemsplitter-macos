import AppKit
import SwiftUI

@main
struct StemSplitterApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        if let url = Bundle.module.url(forResource: "appicon", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, playback: viewModel.playback)
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}
