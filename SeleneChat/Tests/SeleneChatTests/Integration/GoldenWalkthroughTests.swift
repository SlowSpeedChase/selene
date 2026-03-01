import SeleneShared
import XCTest
import SQLite
@testable import SeleneChat

final class GoldenWalkthroughTests: XCTestCase {

    var databaseService: DatabaseService!
    var projectService: ProjectService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_golden_walkthrough_\(UUID().uuidString).db").path

        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath

        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        // Create prerequisite tables not managed by Swift migrations
        // (threads table is created by TypeScript backend migration 013)
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

        try db.run("""
            CREATE TABLE IF NOT EXISTS thread_notes (
                thread_id INTEGER NOT NULL,
                raw_note_id INTEGER NOT NULL,
                relevance_score REAL DEFAULT 1.0,
                added_at TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (thread_id, raw_note_id)
            )
        """)

        // discussion_threads is needed by ProjectService.getActiveProjects() for thread count queries
        try db.run("""
            CREATE TABLE IF NOT EXISTS discussion_threads (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                raw_note_id INTEGER,
                thread_type TEXT NOT NULL DEFAULT 'reflection',
                prompt TEXT NOT NULL DEFAULT '',
                status TEXT DEFAULT 'active',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                surfaced_at TEXT,
                completed_at TEXT,
                related_concepts TEXT,
                test_run TEXT,
                project_id INTEGER,
                thread_name TEXT
            )
        """)

        // Projects and project_notes are created by Migration002 (run by DatabaseService.connect)
        // Configure ProjectService with the test database
        projectService = ProjectService()
        projectService.configure(with: db)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        projectService = nil
        try await super.tearDown()
    }

    // MARK: - Project Creation Defaults

    func testCreateProjectDefaultsToActive() async throws {
        let project = try await projectService.createProject(name: "Test Project")

        XCTAssertEqual(project.status, .active, "User-created projects should default to active, not parked")
        XCTAssertEqual(project.name, "Test Project")
    }

    func testCreateProjectPersistedAsActive() async throws {
        // Create a project
        _ = try await projectService.createProject(name: "Persisted Project")

        // Fetch active projects from the database to verify persistence
        let activeProjects = try await projectService.getActiveProjects()
        let found = activeProjects.first { $0.name == "Persisted Project" }

        XCTAssertNotNil(found, "Project should appear in active projects list")
        XCTAssertEqual(found?.status, .active)
    }
}
