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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

