import XCTest
@testable import LlamaIOS

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testSettingsPersistenceRoundTrip() throws {
        let root = try temporaryDirectory()
        let store = SettingsStore(baseDirectory: root)
        let settings = GenerationSettings(
            temperature: 0.25,
            contextLength: 4096,
            maxTokens: 256,
            seed: 42,
            threads: 3,
            gpuLayers: 12
        )

        try store.save(settings)
        let reloaded = try SettingsStore(baseDirectory: root).load()

        XCTAssertEqual(reloaded, settings)
    }

    func testMigratesLegacySettingsFile() throws {
        let root = try temporaryDirectory()
        let settings = GenerationSettings.default
        let legacyData = try JSONEncoder.appEncoder.encode(settings)
        try legacyData.write(to: root.appending(path: "settings.json"))

        let store = SettingsStore(baseDirectory: root)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded, settings)

        let migratedData = try Data(contentsOf: root.appending(path: "settings.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, PersistentStoreVersion.v2.rawValue)
        XCTAssertNotNil(json["settings"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
