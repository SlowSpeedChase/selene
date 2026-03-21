import SeleneShared
import XCTest
@testable import SeleneChat

final class AppleIntelligenceServiceTests: XCTestCase {

    func testServiceConformsToLLMProvider() {
        // Compile-time check: AppleIntelligenceService must conform to LLMProvider
        if #available(macOS 26, *) {
            let service = AppleIntelligenceService()
            XCTAssertNotNil(service as LLMProvider)
        }
    }

    func testIsAvailableReturnsBoolWithoutCrashing() async {
        if #available(macOS 26, *) {
            let service = AppleIntelligenceService()
            let available = await service.isAvailable()
            // On CI or machines without Apple Intelligence, this may be false
            // Just verify it returns without crashing
            _ = available
        }
    }

    func testLabelTopicReturnsNonEmptyString() async throws {
        if #available(macOS 26, *) {
            let service = AppleIntelligenceService()
            guard await service.isAvailable() else {
                throw XCTSkip("Apple Intelligence not available on this machine")
            }
            let topic = try await service.labelTopic(chunk: "I need to plan the kitchen renovation project and get quotes from contractors this week.")
            XCTAssertFalse(topic.isEmpty, "Topic label should not be empty")
            XCTAssertLessThanOrEqual(topic.count, 60, "Topic label should be concise")
        }
    }
}
