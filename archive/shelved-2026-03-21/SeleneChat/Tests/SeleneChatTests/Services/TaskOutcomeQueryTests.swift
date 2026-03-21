import XCTest
import SeleneShared
@testable import SeleneChat

final class TaskOutcomeQueryTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path
        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    func testGetTaskOutcomesReturnsEmptyForEmptyDB() async throws {
        let outcomes = try await databaseService.getTaskOutcomes(keywords: ["test"], limit: 10)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testGetTaskOutcomesReturnsEmptyForEmptyKeywords() async throws {
        let outcomes = try await databaseService.getTaskOutcomes(keywords: [], limit: 10)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testTaskOutcomeModel() {
        let outcome = TaskOutcome(
            taskTitle: "Wake up at 6am",
            taskType: "action",
            energyRequired: "high",
            estimatedMinutes: 15,
            status: "abandoned",
            createdAt: Date(),
            completedAt: nil,
            daysOpen: 12
        )
        XCTAssertEqual(outcome.taskTitle, "Wake up at 6am")
        XCTAssertEqual(outcome.status, "abandoned")
        XCTAssertEqual(outcome.daysOpen, 12)
    }
}
