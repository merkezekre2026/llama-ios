import SwiftUI

struct AppView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            ChatListView(
                chatStore: appState.chatStore,
                modelStore: appState.modelStore,
                engine: appState.engine,
                settings: $appState.settings
            )
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }

            ModelLibraryView(
                modelStore: appState.modelStore,
                downloader: appState.downloader
            )
            .tabItem {
                Label("Models", systemImage: "externaldrive")
            }

            SettingsView(settings: $appState.settings)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .alert("Startup Error", isPresented: startupErrorBinding) {
            Button("OK", role: .cancel) {
                appState.startupError = nil
            }
        } message: {
            Text(appState.startupError ?? "")
        }
    }

    private var startupErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.startupError != nil },
            set: { if !$0 { appState.startupError = nil } }
        )
    }
}

