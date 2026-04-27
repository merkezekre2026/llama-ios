import XCTest
@testable import LlamaIOS

final class GenerationSettingsTests: XCTestCase {
    func testDefaultSettingsAreUsable() {
        let settings = GenerationSettings.default

        XCTAssertGreaterThan(settings.temperature, 0)
        XCTAssertGreaterThanOrEqual(settings.contextLength, 512)
        XCTAssertGreaterThanOrEqual(settings.maxTokens, 32)
        XCTAssertGreaterThanOrEqual(settings.threads, 1)
        XCTAssertGreaterThanOrEqual(settings.gpuLayers, 0)
    }
}
