import SwiftUI

@main
struct IHaveAlreadySeenItApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 680, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
