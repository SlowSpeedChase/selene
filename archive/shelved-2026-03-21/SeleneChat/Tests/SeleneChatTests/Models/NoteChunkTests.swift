import SeleneShared
import XCTest
@testable import SeleneChat

final class NoteChunkTests: XCTestCase {

    func testNoteChunkInitialization() {
        let chunk = NoteChunk(
            id: 1,
            noteId: 42,
            chunkIndex: 0,
            content: "This is a test chunk about project planning.",
            topic: "project planning",
            tokenCount: 9,
            createdAt: Date()
        )

        XCTAssertEqual(chunk.id, 1)
        XCTAssertEqual(chunk.noteId, 42)
        XCTAssertEqual(chunk.chunkIndex, 0)
        XCTAssertEqual(chunk.content, "This is a test chunk about project planning.")
        XCTAssertEqual(chunk.topic, "project planning")
        XCTAssertEqual(chunk.tokenCount, 9)
    }

    func testNoteChunkTopicIsOptional() {
        let chunk = NoteChunk(
            id: 1,
            noteId: 42,
            chunkIndex: 0,
            content: "Short chunk.",
            topic: nil,
            tokenCount: 2,
            createdAt: Date()
        )

        XCTAssertNil(chunk.topic)
    }

    func testNoteChunkPreviewTruncatesLongContent() {
        let longContent = String(repeating: "word ", count: 100)
        let chunk = NoteChunk(
            id: 1,
            noteId: 1,
            chunkIndex: 0,
            content: longContent,
            topic: nil,
            tokenCount: 100,
            createdAt: Date()
        )

        XCTAssertLessThanOrEqual(chunk.preview.count, 103)
    }

    func testNoteChunkIdentifiable() {
        let chunk = NoteChunk(
            id: 99,
            noteId: 1,
            chunkIndex: 0,
            content: "Test",
            topic: nil,
            tokenCount: 1,
            createdAt: Date()
        )

        XCTAssertEqual(chunk.id, 99)
    }
}
