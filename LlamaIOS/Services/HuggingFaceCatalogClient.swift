import Foundation

enum HuggingFaceCatalogError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Hugging Face catalog request could not be built."
        case .invalidResponse:
            "Hugging Face returned catalog data the app could not read."
        }
    }
}

final class HuggingFaceCatalogClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://huggingface.co")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func searchModels(query: String, sort: ModelCatalogSort = .downloads, limit: Int = 25) async throws -> [CatalogModel] {
        var components = URLComponents(url: baseURL.appending(path: "api/models"), resolvingAgainstBaseURL: false)
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        components?.queryItems = [
            URLQueryItem(name: "search", value: searchText.isEmpty ? "gguf" : searchText),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: sort.queryValue),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "expand", value: "siblings,downloads,likes,lastModified,gguf,tags")
        ]

        guard let url = components?.url else {
            throw HuggingFaceCatalogError.invalidURL
        }

        let responses = try await fetch([HubModelResponse].self, from: url)
        return responses.map(Self.catalogModel(from:))
    }

    func modelDetails(repoId: String) async throws -> CatalogModel {
        let encodedRepoId = repoId
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "api/models/\(encodedRepoId)", relativeTo: baseURL)?.absoluteURL else {
            throw HuggingFaceCatalogError.invalidURL
        }

        return Self.catalogModel(from: try await fetch(HubModelResponse.self, from: url))
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw HuggingFaceCatalogError.invalidResponse
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw HuggingFaceCatalogError.invalidResponse
        }
    }

    private static func catalogModel(from response: HubModelResponse) -> CatalogModel {
        let files = (response.siblings ?? [])
            .compactMap { sibling -> CatalogModelFile? in
                guard sibling.rfilename.lowercased().hasSuffix(".gguf") else {
                    return nil
                }

                let resolvedURL = try? HuggingFaceDownloader.downloadURL(
                    repoId: response.id,
                    filePath: sibling.rfilename
                )

                return CatalogModelFile(
                    filename: sibling.rfilename,
                    sizeBytes: sibling.size,
                    downloadURL: resolvedURL?.absoluteString
                )
            }
            .sorted { lhs, rhs in
                lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }

        return CatalogModel(
            id: response.id,
            downloads: response.downloads,
            likes: response.likes,
            lastModified: parseDate(response.lastModified),
            parameterSize: CatalogModel.inferParameterSize(from: response.id),
            files: files
        )
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

private struct HubModelResponse: Decodable {
    var id: String
    var downloads: Int?
    var likes: Int?
    var lastModified: String?
    var siblings: [HubModelFileResponse]?
}

private struct HubModelFileResponse: Decodable {
    var rfilename: String
    var size: Int64?
}
