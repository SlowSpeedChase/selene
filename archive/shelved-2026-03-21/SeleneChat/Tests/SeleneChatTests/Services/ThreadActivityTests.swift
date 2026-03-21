import XCTest
@testable import SeleneChat

final class ThreadActivityTests: XCTestCase {

    func testRecordThreadActivityInsertsRow() async throws {
        let db = DatabaseService.shared

        // Use a known thread ID (thread 1 should exist in test DB)
        // Record a task_completed activity
        try await db.recordThreadActivity(threadId: 1, type: "task_completed")

        // Verify by reading back
        let activities = try await db.getRecentThreadActivity(threadId: 1, days: 1)
        XCTAssertTrue(activities.contains { $0.activityType == "task_completed" },
                       "Should have recorded a task_completed activity")
    }

    func testRecordThreadActivityRejectsInvalidType() async {
        let db = DatabaseService.shared

        do {
            try await db.recordThreadActivity(threadId: 1, type: "invalid_type")
            XCTFail("Should have thrown for invalid activity type")
        } catch {
            // Expected — CHECK constraint violation
        }
    }
}
