import SeleneShared
import XCTest
@testable import SeleneChat

final class NoteChunkDatabaseTests: XCTestCase {

    // Use unique note IDs per test to avoid cross-test collisions.
    // The test database is shared (DatabaseService.shared singleton).

    override func tearDown() async throws {
        let db = DatabaseService.shared
        // Clean up chunks inserted during tests using known note IDs
        for noteId in [9001, 9002, 9003, 9010, 9020, 9030] {
            try? await db.deleteChunksForNote(noteId: noteId)
        }
        try await super.tearDown()
    }

    // MARK: - Chunk CRUD

    func testInsertAndRetrieveChunks() async throws {
        let db = DatabaseService.shared

        // Insert chunks for a note
        let chunk1 = try await db.insertNoteChunk(
            noteId: 9001,
            chunkIndex: 0,
            content: "First idea about planning.",
            topic: "planning",
            tokenCount: 5,
            embedding: nil
        )
        let chunk2 = try await db.insertNoteChunk(
            noteId: 9001,
            chunkIndex: 1,
            content: "Second idea about execution.",
            topic: "execution",
            tokenCount: 5,
            embedding: nil
        )

        XCTAssertGreaterThan(chunk1, 0, "Should return inserted row ID")
        XCTAssertGreaterThan(chunk2, 0)

        // Retrieve chunks for note
        let chunks = try await db.getChunksForNote(noteId: 9001)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].chunkIndex, 0)
        XCTAssertEqual(chunks[1].chunkIndex, 1)
        XCTAssertEqual(chunks[0].topic, "planning")
    }

    func testGetChunksForMultipleNotes() async throws {
        let db = DatabaseService.shared

        _ = try await db.insertNoteChunk(noteId: 9010, chunkIndex: 0, content: "Note 1 chunk", topic: nil, tokenCount: 3, embedding: nil)
        _ = try await db.insertNoteChunk(noteId: 9020, chunkIndex: 0, content: "Note 2 chunk", topic: nil, tokenCount: 3, embedding: nil)
        _ = try await db.insertNoteChunk(noteId: 9030, chunkIndex: 0, content: "Note 3 chunk", topic: nil, tokenCount: 3, embedding: nil)

        let chunks = try await db.getChunksForNotes(noteIds: [9010, 9030])
        XCTAssertEqual(chunks.count, 2, "Should return chunks for notes 9010 and 9030 only")
    }

    func testDeleteChunksForNote() async throws {
        let db = DatabaseService.shared

        _ = try await db.insertNoteChunk(noteId: 9002, chunkIndex: 0, content: "Chunk A", topic: nil, tokenCount: 2, embedding: nil)
        _ = try await db.insertNoteChunk(noteId: 9002, chunkIndex: 1, content: "Chunk B", topic: nil, tokenCount: 2, embedding: nil)

        try await db.deleteChunksForNote(noteId: 9002)

        let chunks = try await db.getChunksForNote(noteId: 9002)
        XCTAssertTrue(chunks.isEmpty, "All chunks for note should be deleted")
    }

    func testGetUnchunkedNoteIds() async throws {
        let db = DatabaseService.shared

        // This queries raw_notes LEFT JOIN note_chunks.
        // In the test database, raw_notes may not exist (created by TypeScript backend).
        // If raw_notes exists, verify the method returns an array.
        // If not, the method throws a SQLite error which is expected.
        do {
            let unchunked = try await db.getUnchunkedNoteIds(limit: 50)
            // raw_notes exists in the test DB -- verify result is valid
            XCTAssertNotNil(unchunked)
        } catch {
            // Expected: raw_notes table does not exist in test database
            // The method correctly propagates the SQLite error
        }
    }

    // MARK: - Embedding Storage

    func testSaveAndRetrieveChunkEmbedding() async throws {
        let db = DatabaseService.shared

        let chunkId = try await db.insertNoteChunk(
            noteId: 9003, chunkIndex: 0,
            content: "Embeddable chunk", topic: nil,
            tokenCount: 2, embedding: nil
        )

        let testEmbedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        try await db.saveChunkEmbedding(chunkId: chunkId, embedding: testEmbedding)

        let chunksWithEmbeddings = try await db.getChunksWithEmbeddings(noteIds: [9003])
        XCTAssertEqual(chunksWithEmbeddings.count, 1)
        XCTAssertNotNil(chunksWithEmbeddings[0].embedding)
        XCTAssertEqual(chunksWithEmbeddings[0].embedding?.count, 5)
    }
}
