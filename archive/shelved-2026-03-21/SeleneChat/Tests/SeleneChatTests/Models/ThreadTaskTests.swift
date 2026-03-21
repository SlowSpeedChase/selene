import SeleneShared
import XCTest
@testable import SeleneChat

final class ThreadTaskTests: XCTestCase {

    // MARK: - isCompleted

    func testIsCompletedWhenCompletedAtIsNil() {
        let task = ThreadTask(
            id: 1,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: nil
        )
        XCTAssertFalse(task.isCompleted)
    }

    func testIsCompletedWhenCompletedAtIsSet() {
        let task = ThreadTask(
            id: 1,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: Date()
        )
        XCTAssertTrue(task.isCompleted)
    }

    // MARK: - completedDisplay

    func testCompletedDisplayWhenNotCompleted() {
        let task = ThreadTask(
            id: 1,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: nil
        )
        XCTAssertEqual(task.completedDisplay, "")
    }

    func testCompletedDisplayWhenCompleted() {
        let task = ThreadTask(
            id: 1,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: Date()
        )
        // Should start with "Done" and contain relative time
        XCTAssertTrue(task.completedDisplay.hasPrefix("Done "))
    }

    // MARK: - title property

    func testTitleDefaultsToNil() {
        let task = ThreadTask(
            id: 1,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: nil
        )
        XCTAssertNil(task.title)
    }

    func testTitleCanBeSet() {
        var task = ThreadTask(
            id: 1,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: nil
        )
        task.title = "My Task"
        XCTAssertEqual(task.title, "My Task")
    }

    // MARK: - Identifiable / Hashable

    func testIdentifiableUsesId() {
        let task = ThreadTask(
            id: 42,
            threadId: 1,
            thingsTaskId: "ABC123",
            createdAt: Date(),
            completedAt: nil
        )
        XCTAssertEqual(task.id, 42)
    }

    func testHashableEquality() {
        let date = Date()
        let task1 = ThreadTask(id: 1, threadId: 1, thingsTaskId: "ABC", createdAt: date, completedAt: nil)
        let task2 = ThreadTask(id: 1, threadId: 1, thingsTaskId: "ABC", createdAt: date, completedAt: nil)
        XCTAssertEqual(task1, task2)
    }

    func testHashableInequality() {
        let date = Date()
        let task1 = ThreadTask(id: 1, threadId: 1, thingsTaskId: "ABC", createdAt: date, completedAt: nil)
        let task2 = ThreadTask(id: 2, threadId: 1, thingsTaskId: "DEF", createdAt: date, completedAt: nil)
        XCTAssertNotEqual(task1, task2)
    }

    func testCanBeUsedInSet() {
        let date = Date()
        let task1 = ThreadTask(id: 1, threadId: 1, thingsTaskId: "ABC", createdAt: date, completedAt: nil)
        let task2 = ThreadTask(id: 2, threadId: 1, thingsTaskId: "DEF", createdAt: date, completedAt: nil)
        let task3 = ThreadTask(id: 1, threadId: 1, thingsTaskId: "ABC", createdAt: date, completedAt: nil)

        let set: Set<ThreadTask> = [task1, task2, task3]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Mock (DEBUG only)

    func testMockDefaults() {
        let task = ThreadTask.mock()
        XCTAssertEqual(task.id, 1)
        XCTAssertEqual(task.threadId, 1)
        XCTAssertEqual(task.thingsTaskId, "ABC123")
        XCTAssertEqual(task.title, "Sample Task")
        XCTAssertFalse(task.isCompleted)
    }

    func testMockCustomValues() {
        let task = ThreadTask.mock(
            id: 5,
            threadId: 3,
            thingsTaskId: "XYZ789",
            title: "Custom Task",
            completedAt: Date()
        )
        XCTAssertEqual(task.id, 5)
        XCTAssertEqual(task.threadId, 3)
        XCTAssertEqual(task.thingsTaskId, "XYZ789")
        XCTAssertEqual(task.title, "Custom Task")
        XCTAssertTrue(task.isCompleted)
    }
}
