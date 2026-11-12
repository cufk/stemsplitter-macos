import SwiftUI

@main
struct StemSplitterApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}
