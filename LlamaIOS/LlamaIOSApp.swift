import SwiftUI

@main
struct LlamaIOSApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(appState)
                .task {
                    appState.bootstrap()
                }
        }
    }
}

