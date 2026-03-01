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

    // MARK: - Memory Thread Scope

    func testInsertMemoryWithThreadId() async throws {
        let threadId = try insertThread(name: "Test Thread")

        let memoryId = try await databaseService.insertMemory(
            content: "User prefers morning hikes",
            type: .fact,
            confidence: 0.9,
            sourceSessionId: nil,
            threadId: threadId
        )

        XCTAssertGreaterThan(memoryId, 0)

        // Verify thread_id was stored
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        let memoriesTable = Table("conversation_memories")
        let memIdCol = Expression<Int64>("id")
        let threadIdCol = Expression<Int64?>("thread_id")

        let row = try db.pluck(memoriesTable.filter(memIdCol == memoryId))
        let storedThreadId = try row?.get(threadIdCol)

        XCTAssertEqual(storedThreadId, threadId, "Memory should be tagged with thread_id")
    }

    func testInsertMemoryWithoutThreadIdIsNull() async throws {
        let memoryId = try await databaseService.insertMemory(
            content: "User likes coffee",
            type: .preference,
            confidence: 0.8,
            sourceSessionId: nil
        )

        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        let memoriesTable = Table("conversation_memories")
        let memIdCol = Expression<Int64>("id")
        let threadIdCol = Expression<Int64?>("thread_id")

        let row = try db.pluck(memoriesTable.filter(memIdCol == memoryId))
        let storedThreadId = try row?.get(threadIdCol)

        XCTAssertNil(storedThreadId, "General chat memories should have null thread_id")
    }

    // MARK: - Thread Context Isolation

    func testThreadWorkspacePromptOnlyContainsThreadNotes() {
        // Create two threads with distinct content domains
        let joshuaTreeThread = Thread(
            id: 1,
            name: "Joshua Tree Camping Trip",
            why: "Planning a desert camping adventure",
            summary: "Research and logistics for Joshua Tree National Park trip",
            status: "active",
            noteCount: 2,
            createdAt: Date()
        )

        let ceramicsThread = Thread(
            id: 2,
            name: "Ceramics Studio Practice",
            why: "Learning pottery techniques",
            summary: "Notes on ceramics classes and glazing experiments",
            status: "active",
            noteCount: 2,
            createdAt: Date()
        )

        // Joshua Tree notes
        let jtNote1 = Note.mock(
            id: 101,
            title: "Joshua Tree Campsite Research",
            content: "Jumbo Rocks campground looks perfect - 124 sites, first-come first-served. "
                + "Need to arrive early on Friday. Ryan Mountain trail is 3 miles round trip with great sunset views.",
            contentHash: "jt-hash-1",
            wordCount: 30,
            characterCount: 150
        )
        let jtNote2 = Note.mock(
            id: 102,
            title: "Joshua Tree Gear Checklist",
            content: "Pack extra water for desert conditions. "
                + "Bring headlamp for stargazing at Keys View. Check tire pressure for park roads.",
            contentHash: "jt-hash-2",
            wordCount: 25,
            characterCount: 120
        )

        // Ceramics notes (should NOT appear in JT prompt)
        let ceramicsNote1 = Note.mock(
            id: 201,
            title: "Glazing Experiments",
            content: "Tried a new stoneware glaze recipe with iron oxide. "
                + "Cone 6 firing gave beautiful amber tones. Need to test with different clay bodies.",
            contentHash: "cer-hash-1",
            wordCount: 28,
            characterCount: 140
        )
        let ceramicsNote2 = Note.mock(
            id: 202,
            title: "Ceramics Class Notes",
            content: "Centering on the wheel is getting easier. "
                + "Instructor showed wedging technique for removing air bubbles from clay.",
            contentHash: "cer-hash-2",
            wordCount: 22,
            characterCount: 110
        )

        // Build prompt for Joshua Tree thread with ONLY Joshua Tree notes
        let promptBuilder = ThreadWorkspacePromptBuilder()
        let jtPrompt = promptBuilder.buildInitialPrompt(
            thread: joshuaTreeThread,
            notes: [jtNote1, jtNote2],
            tasks: []
        )

        // Prompt should contain Joshua Tree content
        XCTAssertTrue(
            jtPrompt.contains("Joshua Tree"),
            "Thread prompt should contain the thread name"
        )
        XCTAssertTrue(
            jtPrompt.contains("Jumbo Rocks") || jtPrompt.contains("Ryan Mountain"),
            "Thread prompt should contain Joshua Tree note content"
        )

        // Prompt must NOT contain ceramics content
        XCTAssertFalse(
            jtPrompt.contains("ceramics") || jtPrompt.contains("Ceramics"),
            "Thread prompt must not contain content from other threads (ceramics)"
        )
        XCTAssertFalse(
            jtPrompt.contains("glazing") || jtPrompt.contains("Glazing"),
            "Thread prompt must not contain content from other threads (glazing)"
        )
        XCTAssertFalse(
            jtPrompt.contains("stoneware"),
            "Thread prompt must not contain content from other threads (stoneware)"
        )

        // Verify the reverse: ceramics prompt should not contain JT content
        let ceramicsPrompt = promptBuilder.buildInitialPrompt(
            thread: ceramicsThread,
            notes: [ceramicsNote1, ceramicsNote2],
            tasks: []
        )

        XCTAssertTrue(
            ceramicsPrompt.contains("Ceramics"),
            "Ceramics prompt should contain its thread name"
        )
        XCTAssertTrue(
            ceramicsPrompt.contains("stoneware") || ceramicsPrompt.contains("glazing"),
            "Ceramics prompt should contain ceramics note content"
        )
        XCTAssertFalse(
            ceramicsPrompt.contains("Joshua Tree"),
            "Ceramics prompt must not contain Joshua Tree content"
        )
        XCTAssertFalse(
            ceramicsPrompt.contains("Jumbo Rocks") || ceramicsPrompt.contains("Ryan Mountain"),
            "Ceramics prompt must not contain Joshua Tree note details"
        )
    }
}
