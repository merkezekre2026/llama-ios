import XCTest
@testable import LlamaIOS

@MainActor
final class ModelStoreTests: XCTestCase {
    func testImportCopiesModelAndPersistsMetadata() throws {
        let root = try temporaryDirectory()
        let source = root.appending(path: "source.gguf")
        try Data(repeating: 7, count: 32).write(to: source)

        let store = ModelStore(baseDirectory: root.appending(path: "AppSupport"), minimumModelSizeBytes: 16)
        try store.load()

        let record = try store.importModel(from: source)

        XCTAssertEqual(store.models.count, 1)
        XCTAssertEqual(record.displayName, "source")
        XCTAssertEqual(record.source, .imported)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.localPath))
        XCTAssertNotEqual(record.localPath, source.path)

        let reloaded = ModelStore(baseDirectory: root.appending(path: "AppSupport"), minimumModelSizeBytes: 16)
        try reloaded.load()
        XCTAssertEqual(reloaded.models, store.models)
    }

    func testRejectsNonGGUFImport() throws {
        let root = try temporaryDirectory()
        let source = root.appending(path: "source.bin")
        try Data(repeating: 7, count: 32).write(to: source)

        let store = ModelStore(baseDirectory: root.appending(path: "AppSupport"), minimumModelSizeBytes: 16)

        XCTAssertThrowsError(try store.importModel(from: source)) { error in
            XCTAssertEqual(error as? ModelStoreError, .unsupportedFileExtension)
        }
    }

    func testDownloadedMetadataPersists() throws {
        let root = try temporaryDirectory()
        let modelFile = root.appending(path: "model.Q4_K_M.gguf")
        try Data(repeating: 7, count: 32).write(to: modelFile)

        let appSupport = root.appending(path: "AppSupport")
        let store = ModelStore(baseDirectory: appSupport, minimumModelSizeBytes: 16)
        let metadata = ModelDownloadMetadata(
            repoId: "owner/model",
            filename: "model.Q4_K_M.gguf",
            parameterSize: "7B",
            quantization: "Q4_K_M",
            downloadURL: "https://huggingface.co/owner/model/resolve/main/model.Q4_K_M.gguf"
        )

        let record = try store.registerDownloadedModel(at: modelFile, metadata: metadata)
        XCTAssertEqual(record.repoId, "owner/model")
        XCTAssertEqual(record.quantization, "Q4_K_M")

        let reloaded = ModelStore(baseDirectory: appSupport, minimumModelSizeBytes: 16)
        try reloaded.load()

        XCTAssertEqual(reloaded.models.first?.repoId, "owner/model")
        XCTAssertEqual(reloaded.models.first?.filename, "model.Q4_K_M.gguf")
    }

    func testMigratesV1ModelArrayToVersionedStore() throws {
        let root = try temporaryDirectory()
        let appSupport = root.appending(path: "AppSupport")
        let modelsDirectory = appSupport.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelFile = modelsDirectory.appending(path: "legacy.gguf")
        try Data(repeating: 7, count: 32).write(to: modelFile)
        let legacyRecord = ModelRecord(
            displayName: "legacy",
            source: .imported,
            localPath: modelFile.path,
            sizeBytes: 32
        )
        let legacyData = try JSONEncoder.appEncoder.encode([legacyRecord])
        try legacyData.write(to: appSupport.appending(path: "models.json"))

        let store = ModelStore(baseDirectory: appSupport, minimumModelSizeBytes: 16)
        try store.load()

        XCTAssertEqual(store.models.count, 1)

        let migratedData = try Data(contentsOf: appSupport.appending(path: "models.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, PersistentStoreVersion.v2.rawValue)
        XCTAssertNotNil(json["models"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
