import Foundation

@MainActor
final class SettingsStore {
    private let storageURL: URL
    private let fileManager: FileManager

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storageURL = root.appending(path: "settings.json")
    }

    func load() throws -> GenerationSettings {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: storageURL)
        if let store = try? JSONDecoder.appDecoder.decode(VersionedSettingsStore.self, from: data) {
            return store.settings
        }

        let settings = try JSONDecoder.appDecoder.decode(GenerationSettings.self, from: data)
        try save(settings)
        return settings
    }

    func save(_ settings: GenerationSettings) throws {
        let store = VersionedSettingsStore(version: .v2, settings: settings)
        let data = try JSONEncoder.appEncoder.encode(store)
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: [.atomic])
    }
}

private struct VersionedSettingsStore: Codable {
    var version: PersistentStoreVersion
    var settings: GenerationSettings
}
