import SeleneShared
// SeleneChat/Tests/AIProviderTests.swift
import XCTest
@testable import SeleneChat

final class AIProviderTests: XCTestCase {

    func testAIProviderDefaults() {
        XCTAssertEqual(AIProvider.local.displayName, "Local")
        XCTAssertEqual(AIProvider.cloud.displayName, "Cloud")
        XCTAssertEqual(AIProvider.local.icon, "🏠")
        XCTAssertEqual(AIProvider.cloud.icon, "☁️")
    }

    func testAIProviderCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let localData = try encoder.encode(AIProvider.local)
        let decoded = try decoder.decode(AIProvider.self, from: localData)

        XCTAssertEqual(decoded, AIProvider.local)
    }

    func testPlanningMessageWithProvider() {
        let localMessage = PlanningMessage(role: .assistant, content: "Test", provider: .local)
        let cloudMessage = PlanningMessage(role: .assistant, content: "Test", provider: .cloud)

        XCTAssertEqual(localMessage.provider, .local)
        XCTAssertEqual(cloudMessage.provider, .cloud)
    }
}
