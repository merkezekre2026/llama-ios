import SwiftUI

struct ChatListView: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var modelStore: ModelStore

    let engine: LlamaEngine
    @Binding var settings: GenerationSettings

    @State private var selectedSessionID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSessionID) {
                ForEach(chatStore.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)

                        Text(session.updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                }
                .onDelete { offsets in
                    offsets
                        .map { chatStore.sessions[$0] }
                        .forEach(chatStore.deleteSession)
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let session = chatStore.createSession(modelId: modelStore.models.first?.id)
                        selectedSessionID = session.id
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            if let session = selectedSession {
                ChatDetailView(
                    session: session,
                    chatStore: chatStore,
                    modelStore: modelStore,
                    engine: engine,
                    settings: $settings
                )
            } else {
                ContentUnavailableView("Select a Chat", systemImage: "bubble.left")
            }
        }
        .onAppear {
            if selectedSessionID == nil {
                selectedSessionID = chatStore.sessions.first?.id
            }
        }
        .onChange(of: chatStore.sessions) { _, sessions in
            if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = sessions.first?.id
            }
        }
    }

    private var selectedSession: ChatSession? {
        chatStore.sessions.first { $0.id == selectedSessionID }
    }
}

