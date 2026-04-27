import XCTest
@testable import LlamaIOS

final class HuggingFaceDownloaderTests: XCTestCase {
    func testBuildsPublicResolveURL() throws {
        let url = try HuggingFaceDownloader.downloadURL(
            repoId: "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
            filename: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
        )
    }

    func testRejectsInvalidRepoId() {
        XCTAssertThrowsError(try HuggingFaceDownloader.downloadURL(repoId: "missing-owner", filename: "model.gguf")) { error in
            XCTAssertEqual(error as? HuggingFaceDownloadError, .invalidRepoId)
        }
    }

    func testRejectsNonGGUFFilename() {
        XCTAssertThrowsError(try HuggingFaceDownloader.downloadURL(repoId: "owner/model", filename: "model.bin")) { error in
            XCTAssertEqual(error as? HuggingFaceDownloadError, .invalidFilename)
        }
    }
}

