import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var sessions: [ChatSession] = []

    private let storageURL: URL
    private let fileManager: FileManager

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storageURL = root.appending(path: "chats.json")
    }

    func load() throws {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            sessions = []
            return
        }

        let data = try Data(contentsOf: storageURL)
        sessions = try JSONDecoder.appDecoder.decode([ChatSession].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createSession(modelId: UUID?) -> ChatSession {
        let session = ChatSession(title: "New chat", modelId: modelId)
        sessions.insert(session, at: 0)
        try? persist()
        return session
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        try? persist()
    }

    func updateModel(sessionId: UUID, modelId: UUID?) {
        mutate(sessionId) { session in
            session.modelId = modelId
        }
    }

    @discardableResult
    func appendMessage(sessionId: UUID, role: ChatMessage.Role, content: String) -> ChatMessage? {
        var appended: ChatMessage?
        mutate(sessionId) { session in
            let message = ChatMessage(role: role, content: content)
            appended = message
            session.messages.append(message)

            if role == .user, session.title == "New chat" {
                session.title = String(content.prefix(42))
            }
        }
        return appended
    }

    func appendToMessage(sessionId: UUID, messageId: UUID, chunk: String) {
        mutate(sessionId) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            session.messages[index].content += chunk
        }
    }

    func prompt(for session: ChatSession) -> String {
        session.messages.map { message in
            switch message.role {
            case .system:
                "System: \(message.content)"
            case .user:
                "User: \(message.content)"
            case .assistant:
                "Assistant: \(message.content)"
            }
        }
        .joined(separator: "\n")
        + "\nAssistant:"
    }

    private func mutate(_ sessionId: UUID, _ body: (inout ChatSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        body(&sessions[index])
        sessions[index].updatedAt = Date()
        sessions.sort { $0.updatedAt > $1.updatedAt }
        try? persist()
    }

    private func persist() throws {
        let data = try JSONEncoder.appEncoder.encode(sessions)
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: [.atomic])
    }
}

