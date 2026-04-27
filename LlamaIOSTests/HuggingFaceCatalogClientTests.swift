import XCTest
@testable import LlamaIOS

final class HuggingFaceCatalogClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testSearchDecodesPublicGGUFModels() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "huggingface.co")
            let json = """
            [
              {
                "id": "owner/Tiny-1.1B-GGUF",
                "downloads": 123,
                "likes": 7,
                "lastModified": "2026-01-02T03:04:05.000Z",
                "siblings": [
                  { "rfilename": "README.md" },
                  { "rfilename": "tiny-1.1b.Q4_K_M.gguf", "size": 2048 }
                ]
              }
            ]
            """
            return (200, Data(json.utf8))
        }

        let client = HuggingFaceCatalogClient(session: makeSession())
        let results = try await client.searchModels(query: "tiny", sort: .downloads)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "owner/Tiny-1.1B-GGUF")
        XCTAssertEqual(results[0].parameterSize, "1.1B")
        XCTAssertEqual(results[0].files.count, 1)
        XCTAssertEqual(results[0].files[0].quantization, "Q4_K_M")
        XCTAssertEqual(results[0].files[0].sizeBytes, 2048)
    }

    func testSearchAllowsEmptyResults() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("[]".utf8))
        }

        let client = HuggingFaceCatalogClient(session: makeSession())
        let results = try await client.searchModels(query: "nothing")

        XCTAssertEqual(results, [])
    }

    func testInvalidStatusThrowsInvalidResponse() async throws {
        MockURLProtocol.handler = { _ in
            (500, Data("{}".utf8))
        }

        let client = HuggingFaceCatalogClient(session: makeSession())

        do {
            _ = try await client.searchModels(query: "tiny")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? HuggingFaceCatalogError, .invalidResponse)
        }
    }

    func testInvalidJSONThrowsInvalidResponse() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("{".utf8))
        }

        let client = HuggingFaceCatalogClient(session: makeSession())

        do {
            _ = try await client.searchModels(query: "tiny")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? HuggingFaceCatalogError, .invalidResponse)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
