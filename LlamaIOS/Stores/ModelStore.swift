import Foundation

enum ModelStoreError: LocalizedError, Equatable {
    case unsupportedFileExtension
    case fileTooSmall

    var errorDescription: String? {
        switch self {
        case .unsupportedFileExtension:
            "Only .gguf model files are supported."
        case .fileTooSmall:
            "The selected file is too small to be a valid GGUF model."
        }
    }
}

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var models: [ModelRecord] = []

    let modelsDirectory: URL

    private let metadataURL: URL
    private let fileManager: FileManager
    private let minimumModelSizeBytes: Int64

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default,
        minimumModelSizeBytes: Int64 = 1_024
    ) {
        self.fileManager = fileManager
        self.minimumModelSizeBytes = minimumModelSizeBytes

        let root = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = root.appending(path: "Models", directoryHint: .isDirectory)
        self.metadataURL = root.appending(path: "models.json")
    }

    func load() throws {
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            models = []
            return
        }

        let data = try Data(contentsOf: metadataURL)
        let decoded: [ModelRecord]
        if let store = try? JSONDecoder.appDecoder.decode(VersionedModelStore.self, from: data) {
            decoded = store.models
        } else {
            decoded = try JSONDecoder.appDecoder.decode([ModelRecord].self, from: data)
        }

        models = decoded.filter { fileManager.fileExists(atPath: $0.localPath) }
        try persist()
    }

    @discardableResult
    func importModel(from sourceURL: URL) throws -> ModelRecord {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try validateModelFile(sourceURL)
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(for: sourceURL.lastPathComponent)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return try registerModel(at: destinationURL, source: .imported)
    }

    @discardableResult
    func registerDownloadedModel(at fileURL: URL, metadata: ModelDownloadMetadata = ModelDownloadMetadata()) throws -> ModelRecord {
        try validateModelFile(fileURL)
        return try registerModel(at: fileURL, source: .downloaded, metadata: metadata)
    }

    func deleteModel(_ model: ModelRecord) {
        try? fileManager.removeItem(at: URL(fileURLWithPath: model.localPath))
        models.removeAll { $0.id == model.id }
        try? persist()
    }

    func model(withID id: UUID?) -> ModelRecord? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    func markUsed(modelId: UUID) {
        guard let index = models.firstIndex(where: { $0.id == modelId }) else { return }
        models[index].lastUsedAt = Date()
        try? persist()
    }

    func uniqueDestinationURL(for filename: String) -> URL {
        let sanitized = filename.isEmpty ? "model.gguf" : filename
        let baseName = URL(fileURLWithPath: sanitized).deletingPathExtension().lastPathComponent
        let pathExtension = URL(fileURLWithPath: sanitized).pathExtension.isEmpty ? "gguf" : URL(fileURLWithPath: sanitized).pathExtension
        var candidate = modelsDirectory.appending(path: "\(baseName).\(pathExtension)")
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = modelsDirectory.appending(path: "\(baseName)-\(index).\(pathExtension)")
            index += 1
        }

        return candidate
    }

    private func registerModel(
        at fileURL: URL,
        source: ModelSource,
        metadata: ModelDownloadMetadata = ModelDownloadMetadata()
    ) throws -> ModelRecord {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = attributes[.size] as? NSNumber
        let record = ModelRecord(
            displayName: fileURL.deletingPathExtension().lastPathComponent,
            source: source,
            localPath: fileURL.path,
            sizeBytes: size?.int64Value ?? 0,
            repoId: metadata.repoId,
            filename: metadata.filename,
            parameterSize: metadata.parameterSize,
            quantization: metadata.quantization,
            downloadURL: metadata.downloadURL
        )

        models.removeAll { $0.localPath == record.localPath }
        models.insert(record, at: 0)
        try persist()
        return record
    }

    private func validateModelFile(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "gguf" else {
            throw ModelStoreError.unsupportedFileExtension
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= minimumModelSizeBytes else {
            throw ModelStoreError.fileTooSmall
        }
    }

    private func persist() throws {
        let store = VersionedModelStore(version: .v2, models: models)
        let data = try JSONEncoder.appEncoder.encode(store)
        try fileManager.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: metadataURL, options: [.atomic])
    }
}

private struct VersionedModelStore: Codable {
    var version: PersistentStoreVersion
    var models: [ModelRecord]
}
