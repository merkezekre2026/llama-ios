import SwiftUI

struct AppView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: AppTab = .chats
    @State private var selectedChatSessionID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatListView(
                chatStore: appState.chatStore,
                modelStore: appState.modelStore,
                engine: appState.engine,
                settings: $appState.settings,
                selectedSessionID: $selectedChatSessionID
            )
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AppTab.chats)

            ModelLibraryView(
                modelStore: appState.modelStore,
                downloader: appState.downloader,
                catalogClient: appState.catalogClient
            ) { model in
                let session = appState.chatStore.createSession(modelId: model.id)
                selectedChatSessionID = session.id
                selectedTab = .chats
            }
            .tabItem {
                Label("Models", systemImage: "externaldrive")
            }
            .tag(AppTab.models)

            SettingsView(settings: $appState.settings)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(AppTab.settings)
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

private enum AppTab: Hashable {
    case chats
    case models
    case settings
}
