import XCTest
import SQLite
import SeleneShared
@testable import SeleneChat

final class EmotionalHistoryQueryTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path
        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath

        // Create the raw_notes and processed_notes tables needed for emotional queries
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        try db.run("""
            CREATE TABLE IF NOT EXISTS raw_notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL DEFAULT '',
                content TEXT NOT NULL DEFAULT '',
                content_hash TEXT NOT NULL DEFAULT '',
                source_type TEXT NOT NULL DEFAULT 'test',
                word_count INTEGER NOT NULL DEFAULT 0,
                character_count INTEGER NOT NULL DEFAULT 0,
                tags TEXT,
                created_at TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT '',
                processed_at TEXT,
                exported_at TEXT,
                status TEXT NOT NULL DEFAULT 'processed',
                exported_to_obsidian INTEGER NOT NULL DEFAULT 0,
                source_uuid TEXT,
                test_run TEXT,
                calendar_event TEXT
            )
        """)

        try db.run("""
            CREATE TABLE IF NOT EXISTS processed_notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                raw_note_id INTEGER NOT NULL,
                concepts TEXT,
                concept_confidence TEXT,
                primary_theme TEXT,
                secondary_themes TEXT,
                theme_confidence REAL,
                overall_sentiment TEXT,
                sentiment_score REAL,
                emotional_tone TEXT,
                energy_level TEXT,
                essence TEXT,
                fidelity_tier TEXT,
                FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
            )
        """)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    func testGetEmotionalNotesReturnsEmptyForEmptyDB() async throws {
        let notes = try await databaseService.getEmotionalNotes(
            keywords: ["morning", "routine"],
            limit: 5
        )
        XCTAssertNotNil(notes)
        XCTAssertTrue(notes.isEmpty)
    }

    func testGetEmotionalNotesReturnsEmptyForEmptyKeywords() async throws {
        let notes = try await databaseService.getEmotionalNotes(
            keywords: [],
            limit: 5
        )
        XCTAssertTrue(notes.isEmpty)
    }

    func testGetEmotionalNotesMethodExists() async throws {
        // Verify the method signature compiles and is callable
        let _: [Note] = try await databaseService.getEmotionalNotes(
            keywords: ["test"],
            limit: 10
        )
    }
}
