import Foundation

enum HuggingFaceDownloadError: LocalizedError, Equatable {
    case invalidRepoId
    case invalidFilename
    case invalidResponse
    case fileTooSmall

    var errorDescription: String? {
        switch self {
        case .invalidRepoId:
            "Enter a public Hugging Face repo id like owner/model-name."
        case .invalidFilename:
            "Enter a GGUF filename ending in .gguf."
        case .invalidResponse:
            "Hugging Face did not return a downloadable model file."
        case .fileTooSmall:
            "Downloaded file is too small to be a valid GGUF model."
        }
    }
}

@MainActor
final class HuggingFaceDownloader: NSObject, ObservableObject {
    @Published private(set) var progress: Double?
    @Published private(set) var activeFilename: String?

    private var continuation: CheckedContinuation<URL, Error>?
    private var destinationURL: URL?
    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private let minimumModelSizeBytes: Int64

    init(minimumModelSizeBytes: Int64 = 1_024) {
        self.minimumModelSizeBytes = minimumModelSizeBytes
    }

    static func downloadURL(repoId: String, filename: String) throws -> URL {
        let repo = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = filename.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidRepoId(repo) else {
            throw HuggingFaceDownloadError.invalidRepoId
        }

        guard isValidGGUFFilename(file) else {
            throw HuggingFaceDownloadError.invalidFilename
        }

        guard let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)") else {
            throw HuggingFaceDownloadError.invalidFilename
        }

        return url
    }

    static func downloadURL(repoId: String, filePath: String) throws -> URL {
        let repo = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = filePath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidRepoId(repo) else {
            throw HuggingFaceDownloadError.invalidRepoId
        }

        guard isValidGGUFFilePath(file) else {
            throw HuggingFaceDownloadError.invalidFilename
        }

        let encodedRepo = repo
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let encodedFile = file
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        guard let url = URL(string: "https://huggingface.co/\(encodedRepo)/resolve/main/\(encodedFile)") else {
            throw HuggingFaceDownloadError.invalidFilename
        }

        return url
    }

    func download(repoId: String, filename: String, destinationDirectory: URL) async throws -> URL {
        let url = try Self.downloadURL(repoId: repoId, filename: filename)
        return try await download(from: url, localFilename: filename, destinationDirectory: destinationDirectory)
    }

    func download(repoId: String, filePath: String, destinationDirectory: URL) async throws -> URL {
        let url = try Self.downloadURL(repoId: repoId, filePath: filePath)
        let localFilename = URL(fileURLWithPath: filePath).lastPathComponent
        return try await download(from: url, localFilename: localFilename, destinationDirectory: destinationDirectory)
    }

    private func download(from url: URL, localFilename: String, destinationDirectory: URL) async throws -> URL {
        let targetURL = uniqueDestinationURL(for: localFilename, in: destinationDirectory)

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        return try await withCheckedThrowingContinuation { continuation in
            self.progress = 0
            self.activeFilename = localFilename
            self.continuation = continuation
            self.destinationURL = targetURL

            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            let task = session.downloadTask(with: request)
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        progress = nil
        activeFilename = nil
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    private static func isValidRepoId(_ repoId: String) -> Bool {
        let pieces = repoId.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return false }
        return pieces.allSatisfy { piece in
            !piece.isEmpty && piece.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
            }
        }
    }

    private static func isValidGGUFFilename(_ filename: String) -> Bool {
        guard filename.lowercased().hasSuffix(".gguf") else { return false }
        guard !filename.contains(".."), !filename.contains("/"), !filename.contains("\\") else { return false }
        return !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValidGGUFFilePath(_ filePath: String) -> Bool {
        guard filePath.lowercased().hasSuffix(".gguf") else { return false }
        guard !filePath.contains(".."), !filePath.contains("\\") else { return false }
        return filePath.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        let stem = URL(fileURLWithPath: safeName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: safeName).pathExtension
        var candidate = directory.appending(path: safeName)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(stem)-\(index).\(ext)")
            index += 1
        }

        return candidate
    }

    private func reset() {
        progress = nil
        activeFilename = nil
        task = nil
        destinationURL = nil
        continuation = nil
    }
}

extension HuggingFaceDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let nextProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.progress = nextProgress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard let destinationURL else { return }

            do {
                if let response = downloadTask.response as? HTTPURLResponse,
                   !(200..<300).contains(response.statusCode) {
                    throw HuggingFaceDownloadError.invalidResponse
                }

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: location, to: destinationURL)

                let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard size >= minimumModelSizeBytes else {
                    try? FileManager.default.removeItem(at: destinationURL)
                    throw HuggingFaceDownloadError.fileTooSmall
                }

                continuation?.resume(returning: destinationURL)
            } catch {
                continuation?.resume(throwing: error)
            }

            reset()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            continuation?.resume(throwing: error)
            reset()
        }
    }
}
