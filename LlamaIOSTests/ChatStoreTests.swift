import XCTest
@testable import LlamaIOS

@MainActor
final class ChatStoreTests: XCTestCase {
    func testChatPersistenceRoundTrip() throws {
        let root = try temporaryDirectory()
        let modelId = UUID()
        let store = ChatStore(baseDirectory: root)

        let session = store.createSession(modelId: modelId)
        store.appendMessage(sessionId: session.id, role: .user, content: "Hello")
        store.appendMessage(sessionId: session.id, role: .assistant, content: "Hi")

        let reloaded = ChatStore(baseDirectory: root)
        try reloaded.load()

        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions[0].modelId, modelId)
        XCTAssertEqual(reloaded.sessions[0].messages.map(\.content), ["Hello", "Hi"])
    }

    func testPromptFormatting() {
        let store = ChatStore()
        let session = ChatSession(
            title: "Test",
            modelId: nil,
            messages: [
                ChatMessage(role: .user, content: "Hello"),
                ChatMessage(role: .assistant, content: "Hi")
            ]
        )

        XCTAssertEqual(store.prompt(for: session), "User: Hello\nAssistant: Hi\nAssistant:")
    }

    func testMigratesV1ChatArrayToVersionedStore() throws {
        let root = try temporaryDirectory()
        let modelId = UUID()
        let session = ChatSession(
            title: "Legacy",
            modelId: modelId,
            messages: [ChatMessage(role: .user, content: "Hello")]
        )
        let legacyData = try JSONEncoder.appEncoder.encode([session])
        try legacyData.write(to: root.appending(path: "chats.json"))

        let store = ChatStore(baseDirectory: root)
        try store.load()

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].title, "Legacy")

        let migratedData = try Data(contentsOf: root.appending(path: "chats.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, PersistentStoreVersion.v2.rawValue)
        XCTAssertNotNil(json["sessions"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
