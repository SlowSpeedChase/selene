import SeleneShared
import XCTest
import SQLite
@testable import SeleneChat

final class Migration009ThreadTasksTests: XCTestCase {

    var db: Connection!

    override func setUpWithError() throws {
        db = try Connection(.inMemory)

        // Create prerequisite threads table (migration depends on it via FK)
        try db.run("""
            CREATE TABLE threads (
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
    }

    override func tearDown() {
        db = nil
    }

    // MARK: - Migration runs

    func testMigrationCreatesThreadTasksTable() throws {
        try Migration009_ThreadTasks.run(db: db)

        // Verify table exists
        let count = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='thread_tasks'"
        ) as! Int64
        XCTAssertEqual(count, 1)
    }

    func testMigrationCreatesIndexes() throws {
        try Migration009_ThreadTasks.run(db: db)

        // Check thread index
        let threadIdx = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_thread_tasks_thread'"
        ) as! Int64
        XCTAssertEqual(threadIdx, 1)

        // Check things index
        let thingsIdx = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_thread_tasks_things'"
        ) as! Int64
        XCTAssertEqual(thingsIdx, 1)
    }

    func testMigrationIsIdempotent() throws {
        // Running twice should not error (IF NOT EXISTS)
        try Migration009_ThreadTasks.run(db: db)
        try Migration009_ThreadTasks.run(db: db)

        let count = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='thread_tasks'"
        ) as! Int64
        XCTAssertEqual(count, 1)
    }

    // MARK: - Schema correctness

    func testCanInsertThreadTask() throws {
        try Migration009_ThreadTasks.run(db: db)

        // Insert a thread first (FK requirement)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        // Insert a thread task
        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-ABC123')
        """)

        let count = try db.scalar("SELECT COUNT(*) FROM thread_tasks") as! Int64
        XCTAssertEqual(count, 1)
    }

    func testUniqueConstraintPreventsduplicates() throws {
        try Migration009_ThreadTasks.run(db: db)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-ABC123')
        """)

        // Same thread_id + things_task_id should fail
        XCTAssertThrowsError(try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-ABC123')
        """))
    }

    func testDifferentThingsTaskIdsAllowed() throws {
        try Migration009_ThreadTasks.run(db: db)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-AAA')
        """)
        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-BBB')
        """)

        let count = try db.scalar("SELECT COUNT(*) FROM thread_tasks") as! Int64
        XCTAssertEqual(count, 2)
    }

    func testCreatedAtDefaultsToCurrentTimestamp() throws {
        try Migration009_ThreadTasks.run(db: db)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-ABC123')
        """)

        let createdAt = try db.scalar(
            "SELECT created_at FROM thread_tasks WHERE id = 1"
        ) as? String
        XCTAssertNotNil(createdAt)
    }

    func testCompletedAtDefaultsToNull() throws {
        try Migration009_ThreadTasks.run(db: db)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-ABC123')
        """)

        let completedAt = try db.scalar(
            "SELECT completed_at FROM thread_tasks WHERE id = 1"
        ) as? String
        XCTAssertNil(completedAt)
    }

    func testCanSetCompletedAt() throws {
        try Migration009_ThreadTasks.run(db: db)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        try db.run("""
            INSERT INTO thread_tasks (thread_id, things_task_id)
            VALUES (1, 'THINGS-ABC123')
        """)

        try db.run("""
            UPDATE thread_tasks SET completed_at = '2026-02-06 12:00:00'
            WHERE id = 1
        """)

        let completedAt = try db.scalar(
            "SELECT completed_at FROM thread_tasks WHERE id = 1"
        ) as? String
        XCTAssertEqual(completedAt, "2026-02-06 12:00:00")
    }

    func testAutoIncrementId() throws {
        try Migration009_ThreadTasks.run(db: db)
        try db.run("INSERT INTO threads (name) VALUES ('Test Thread')")

        try db.run("INSERT INTO thread_tasks (thread_id, things_task_id) VALUES (1, 'AAA')")
        try db.run("INSERT INTO thread_tasks (thread_id, things_task_id) VALUES (1, 'BBB')")

        let id1 = try db.scalar("SELECT id FROM thread_tasks WHERE things_task_id = 'AAA'") as! Int64
        let id2 = try db.scalar("SELECT id FROM thread_tasks WHERE things_task_id = 'BBB'") as! Int64
        XCTAssertEqual(id2, id1 + 1)
    }
}
