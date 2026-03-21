import SeleneShared
import XCTest
@testable import SeleneChat

final class MemoryBackfillTests: XCTestCase {

    /// Track memory IDs we insert so we can clean up after each test
    private var insertedMemoryIds: [Int64] = []

    override func tearDown() async throws {
        let databaseService = DatabaseService.shared
        for id in insertedMemoryIds {
            try? await databaseService.deleteMemory(id: id)
        }
        insertedMemoryIds = []
        try await super.tearDown()
    }

    func testBackfillEmbedsMemoriesWithoutEmbeddings() async throws {
        let ollamaService = OllamaService.shared
        let isAvailable = await ollamaService.isAvailable()
        try XCTSkipUnless(isAvailable, "Ollama not running - skipping integration test")

        let databaseService = DatabaseService.shared
        let memoryService = MemoryService.shared
        let sessionId = UUID()

        // Insert memories WITHOUT embeddings
        let id1 = try await databaseService.insertMemory(
            content: "User prefers dark mode",
            type: .preference,
            confidence: 0.9,
            sourceSessionId: sessionId
        )
        insertedMemoryIds.append(id1)

        let id2 = try await databaseService.insertMemory(
            content: "User is building Selene",
            type: .fact,
            confidence: 0.8,
            sourceSessionId: sessionId
        )
        insertedMemoryIds.append(id2)

        // Verify no embeddings on our inserted memories
        let before = try await databaseService.getAllMemoriesWithEmbeddings()
        let ourMemoriesBefore = before.filter { insertedMemoryIds.contains($0.memory.id) }
        let withoutBefore = ourMemoriesBefore.filter { $0.embedding == nil }
        XCTAssertEqual(withoutBefore.count, 2, "Both memories should lack embeddings")

        // Run backfill
        let count = try await memoryService.backfillEmbeddings()
        XCTAssertGreaterThanOrEqual(count, 2, "Should have backfilled at least our 2 memories")

        // Verify embeddings now exist on our memories
        let after = try await databaseService.getAllMemoriesWithEmbeddings()
        let ourMemoriesAfter = after.filter { insertedMemoryIds.contains($0.memory.id) }
        let withoutAfter = ourMemoriesAfter.filter { $0.embedding == nil }
        XCTAssertEqual(withoutAfter.count, 0, "All our memories should now have embeddings")

        for result in ourMemoriesAfter {
            XCTAssertEqual(result.embedding?.count, 768, "Each embedding should be 768-dim")
        }
    }

    func testBackfillSkipsMemoriesWithEmbeddings() async throws {
        let ollamaService = OllamaService.shared
        let isAvailable = await ollamaService.isAvailable()
        try XCTSkipUnless(isAvailable, "Ollama not running - skipping integration test")

        let databaseService = DatabaseService.shared
        let memoryService = MemoryService.shared
        let sessionId = UUID()
        let existingEmbedding = try await ollamaService.embed(text: "test")

        let id1 = try await databaseService.insertMemory(
            content: "Already embedded memory for backfill test",
            type: .fact,
            confidence: 0.8,
            sourceSessionId: sessionId,
            embedding: existingEmbedding
        )
        insertedMemoryIds.append(id1)

        // Run backfill and verify our already-embedded memory still has its original embedding
        _ = try await memoryService.backfillEmbeddings()

        let allMemories = try await databaseService.getAllMemoriesWithEmbeddings()
        let ourMemory = allMemories.first { $0.memory.id == id1 }
        XCTAssertNotNil(ourMemory, "Our memory should still exist")
        XCTAssertNotNil(ourMemory?.embedding, "Embedding should still be present")
        XCTAssertEqual(ourMemory?.embedding?.count, 768, "Embedding should still be 768-dim")
    }

    func testBackfillIsIdempotent() async throws {
        let ollamaService = OllamaService.shared
        let isAvailable = await ollamaService.isAvailable()
        try XCTSkipUnless(isAvailable, "Ollama not running - skipping integration test")

        let databaseService = DatabaseService.shared
        let memoryService = MemoryService.shared
        let sessionId = UUID()

        let id1 = try await databaseService.insertMemory(
            content: "Test memory for idempotent backfill",
            type: .fact,
            confidence: 0.8,
            sourceSessionId: sessionId
        )
        insertedMemoryIds.append(id1)

        let count1 = try await memoryService.backfillEmbeddings()
        XCTAssertGreaterThanOrEqual(count1, 1, "First run should backfill at least 1")

        let count2 = try await memoryService.backfillEmbeddings()
        XCTAssertEqual(count2, 0, "Second run should backfill 0 (idempotent)")
    }
}
