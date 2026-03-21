import SeleneShared
import XCTest
import SQLite
@testable import SeleneChat

final class ThreadWorkspaceIntegrationTests: XCTestCase {

    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_thread_workspace_\(UUID().uuidString).db").path

        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath

        // Create prerequisite tables not managed by Swift migrations
        // (threads table is created by TypeScript backend migration 013)
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        try db.run("""
            CREATE TABLE IF NOT EXISTS threads (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                why TEXT,
                summary TEXT,
                status TEXT DEFAULT 'active',
                note_count INTEGER DEFAULT 0,
                momentum_score REAL,
                last_activity_at TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)

        // Ensure thread_tasks table exists (should be created by Migration009)
        try Migration009_ThreadTasks.run(db: db)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func insertThread(name: String, why: String? = nil, summary: String? = nil, status: String = "active") throws -> Int64 {
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return -1
        }

        let threadsTable = Table("threads")
        let nameCol = SQLite.Expression<String>("name")
        let whyCol = SQLite.Expression<String?>("why")
        let summaryCol = SQLite.Expression<String?>("summary")
        let statusCol = SQLite.Expression<String>("status")
        let noteCountCol = SQLite.Expression<Int64>("note_count")

        try db.run(threadsTable.insert(
            nameCol <- name,
            whyCol <- why,
            summaryCol <- summary,
            statusCol <- status,
            noteCountCol <- 0
        ))

        return db.lastInsertRowid
    }

    // MARK: - getTasksForThread

    func testGetTasksForThreadReturnsEmptyWhenNoTasks() async throws {
        let threadId = try insertThread(name: "Empty Thread")

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 0)
    }

    func testGetTasksForThreadReturnsTasks() async throws {
        let threadId = try insertThread(name: "Test Thread")

        // Insert tasks directly
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "THINGS-001")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "THINGS-002")

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 2)

        let taskIds = tasks.map { $0.thingsTaskId }
        XCTAssertTrue(taskIds.contains("THINGS-001"))
        XCTAssertTrue(taskIds.contains("THINGS-002"))
    }

    func testGetTasksForThreadReturnsCorrectFields() async throws {
        let threadId = try insertThread(name: "Test Thread")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "THINGS-XYZ")

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 1)

        let task = tasks[0]
        XCTAssertEqual(task.threadId, threadId)
        XCTAssertEqual(task.thingsTaskId, "THINGS-XYZ")
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
    }

    func testGetTasksForThreadOnlyReturnsTasksForGivenThread() async throws {
        let thread1 = try insertThread(name: "Thread 1")
        let thread2 = try insertThread(name: "Thread 2")

        try await databaseService.linkTaskToThread(threadId: thread1, thingsTaskId: "TASK-A")
        try await databaseService.linkTaskToThread(threadId: thread2, thingsTaskId: "TASK-B")
        try await databaseService.linkTaskToThread(threadId: thread1, thingsTaskId: "TASK-C")

        let tasks1 = try await databaseService.getTasksForThread(thread1)
        XCTAssertEqual(tasks1.count, 2)

        let tasks2 = try await databaseService.getTasksForThread(thread2)
        XCTAssertEqual(tasks2.count, 1)
        XCTAssertEqual(tasks2[0].thingsTaskId, "TASK-B")
    }

    func testGetTasksForThreadOrdersByCreatedAtDescending() async throws {
        let threadId = try insertThread(name: "Test Thread")
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        // Insert with explicit timestamps to guarantee ordering
        // (CURRENT_TIMESTAMP has second-level precision, too coarse for fast inserts)
        let threadTasksTable = Table("thread_tasks")
        let threadIdCol = SQLite.Expression<Int64>("thread_id")
        let thingsTaskIdCol = SQLite.Expression<String>("things_task_id")
        let createdAtCol = SQLite.Expression<String>("created_at")

        try db.run(threadTasksTable.insert(
            threadIdCol <- threadId,
            thingsTaskIdCol <- "FIRST",
            createdAtCol <- "2026-02-06 10:00:00"
        ))
        try db.run(threadTasksTable.insert(
            threadIdCol <- threadId,
            thingsTaskIdCol <- "SECOND",
            createdAtCol <- "2026-02-06 11:00:00"
        ))

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 2)
        // Most recent first (desc order)
        XCTAssertEqual(tasks[0].thingsTaskId, "SECOND")
        XCTAssertEqual(tasks[1].thingsTaskId, "FIRST")
    }

    // MARK: - linkTaskToThread

    func testLinkTaskToThreadCreatesRecord() async throws {
        let threadId = try insertThread(name: "Test Thread")

        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "NEW-TASK")

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].thingsTaskId, "NEW-TASK")
    }

    func testLinkTaskToThreadIgnoresDuplicates() async throws {
        let threadId = try insertThread(name: "Test Thread")

        // Link same task twice (INSERT OR IGNORE)
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "SAME-TASK")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "SAME-TASK")

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 1, "Duplicate should be ignored")
    }

    // MARK: - markThreadTaskCompleted

    func testMarkThreadTaskCompleted() async throws {
        let threadId = try insertThread(name: "Test Thread")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "COMPLETE-ME")

        // Verify not completed initially
        var tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertFalse(tasks[0].isCompleted)

        // Mark completed
        try await databaseService.markThreadTaskCompleted(thingsTaskId: "COMPLETE-ME")

        // Verify completed
        tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertTrue(tasks[0].isCompleted)
        XCTAssertNotNil(tasks[0].completedAt)
    }

    func testMarkThreadTaskCompletedWithCustomDate() async throws {
        let threadId = try insertThread(name: "Test Thread")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "DATED-TASK")

        let completionDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
        try await databaseService.markThreadTaskCompleted(thingsTaskId: "DATED-TASK", completedAt: completionDate)

        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertTrue(tasks[0].isCompleted)
        XCTAssertNotNil(tasks[0].completedAt)

        // Verify the date is close to what we set (within 1 second tolerance)
        let timeDiff = abs(tasks[0].completedAt!.timeIntervalSince(completionDate))
        XCTAssertLessThan(timeDiff, 1.0, "Completion date should match within 1 second")
    }

    // MARK: - getThreadById

    func testGetThreadByIdReturnsThread() async throws {
        let threadId = try insertThread(
            name: "ADHD System Design",
            why: "Build tools that externalize executive function",
            summary: "Exploring approaches to reduce cognitive load",
            status: "active"
        )

        let thread = try await databaseService.getThreadById(threadId)
        XCTAssertNotNil(thread)
        XCTAssertEqual(thread?.name, "ADHD System Design")
        XCTAssertEqual(thread?.why, "Build tools that externalize executive function")
        XCTAssertEqual(thread?.summary, "Exploring approaches to reduce cognitive load")
        XCTAssertEqual(thread?.status, "active")
    }

    func testGetThreadByIdReturnsNilForInvalidId() async throws {
        let thread = try await databaseService.getThreadById(999)
        XCTAssertNil(thread)
    }

    func testGetThreadByIdHandlesNullOptionalFields() async throws {
        let threadId = try insertThread(name: "Minimal Thread")

        let thread = try await databaseService.getThreadById(threadId)
        XCTAssertNotNil(thread)
        XCTAssertEqual(thread?.name, "Minimal Thread")
        XCTAssertNil(thread?.why)
        XCTAssertNil(thread?.summary)
    }

    // MARK: - End-to-end workspace flow

    func testWorkspaceFlowThreadWithTasks() async throws {
        // Create a thread
        let threadId = try insertThread(
            name: "Voice Input Feature",
            why: "Reduce friction for quick captures",
            summary: "Phase 1 complete with push-to-talk"
        )

        // Link some tasks
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "VOICE-001")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "VOICE-002")
        try await databaseService.linkTaskToThread(threadId: threadId, thingsTaskId: "VOICE-003")

        // Complete one
        try await databaseService.markThreadTaskCompleted(thingsTaskId: "VOICE-002")

        // Load thread
        let thread = try await databaseService.getThreadById(threadId)
        XCTAssertNotNil(thread)
        XCTAssertEqual(thread?.name, "Voice Input Feature")

        // Load tasks
        let tasks = try await databaseService.getTasksForThread(threadId)
        XCTAssertEqual(tasks.count, 3)

        let completedTasks = tasks.filter { $0.isCompleted }
        let openTasks = tasks.filter { !$0.isCompleted }
        XCTAssertEqual(completedTasks.count, 1)
        XCTAssertEqual(openTasks.count, 2)
        XCTAssertEqual(completedTasks[0].thingsTaskId, "VOICE-002")
    }
}
