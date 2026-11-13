import SwiftUI

@main
struct StemSplitterApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, playback: viewModel.playback)
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}
