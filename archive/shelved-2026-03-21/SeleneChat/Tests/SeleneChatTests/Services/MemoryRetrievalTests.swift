import SeleneShared
import XCTest
@testable import SeleneChat

final class MemoryRetrievalTests: XCTestCase {

    func testFindSimilarMemoriesRanksBySimilarity() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let memories: [(memory: ConversationMemory, embedding: [Float]?)] = [
            (memory: ConversationMemory(id: 1, content: "very similar", memoryType: .fact, confidence: 1.0),
             embedding: [0.9, 0.1, 0.0]),
            (memory: ConversationMemory(id: 2, content: "somewhat similar", memoryType: .fact, confidence: 1.0),
             embedding: [0.5, 0.5, 0.5]),
            (memory: ConversationMemory(id: 3, content: "not similar", memoryType: .fact, confidence: 1.0),
             embedding: [0.0, 0.0, 1.0]),
            (memory: ConversationMemory(id: 4, content: "no embedding", memoryType: .fact, confidence: 1.0),
             embedding: nil),
        ]

        let results = MemoryService.findSimilarMemories(
            queryEmbedding: queryEmbedding,
            memories: memories,
            threshold: 0.3,
            limit: 10
        )

        XCTAssertEqual(results.count, 2, "Should return 2 memories above threshold 0.3")
        XCTAssertEqual(results[0].memory.id, 1, "Most similar should be first")
        XCTAssertEqual(results[1].memory.id, 2, "Second most similar should be second")
    }

    func testFindSimilarMemoriesRespectsThreshold() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let memories: [(memory: ConversationMemory, embedding: [Float]?)] = [
            (memory: ConversationMemory(id: 1, content: "barely similar", memoryType: .fact, confidence: 1.0),
             embedding: [0.5, 0.5, 0.5]),
        ]

        let strict = MemoryService.findSimilarMemories(
            queryEmbedding: queryEmbedding,
            memories: memories,
            threshold: 0.7,
            limit: 10
        )
        XCTAssertEqual(strict.count, 0)

        let loose = MemoryService.findSimilarMemories(
            queryEmbedding: queryEmbedding,
            memories: memories,
            threshold: 0.5,
            limit: 10
        )
        XCTAssertEqual(loose.count, 1)
    }

    func testFindSimilarMemoriesRespectsLimit() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let memories: [(memory: ConversationMemory, embedding: [Float]?)] = (1...10).map { i in
            (memory: ConversationMemory(id: Int64(i), content: "memory \(i)", memoryType: .fact, confidence: 1.0),
             embedding: [Float(10 - i) / 10.0, 0.1, 0.0])
        }

        let results = MemoryService.findSimilarMemories(
            queryEmbedding: queryEmbedding,
            memories: memories,
            threshold: 0.0,
            limit: 3
        )

        XCTAssertEqual(results.count, 3)
    }

    func testFindSimilarMemoriesWeightsByConfidence() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let memories: [(memory: ConversationMemory, embedding: [Float]?)] = [
            (memory: ConversationMemory(id: 1, content: "high confidence", memoryType: .fact, confidence: 1.0),
             embedding: [0.8, 0.2, 0.0]),
            (memory: ConversationMemory(id: 2, content: "low confidence", memoryType: .fact, confidence: 0.1),
             embedding: [0.9, 0.1, 0.0]),
        ]

        let results = MemoryService.findSimilarMemories(
            queryEmbedding: queryEmbedding,
            memories: memories,
            threshold: 0.0,
            limit: 10
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].memory.id, 1, "High confidence memory should rank first")
    }

    func testFindSimilarMemoriesHandlesNoEmbeddings() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let memories: [(memory: ConversationMemory, embedding: [Float]?)] = [
            (memory: ConversationMemory(id: 1, content: "no embedding", memoryType: .fact, confidence: 1.0),
             embedding: nil),
        ]

        let results = MemoryService.findSimilarMemories(
            queryEmbedding: queryEmbedding,
            memories: memories,
            threshold: 0.0,
            limit: 10
        )

        XCTAssertEqual(results.count, 0, "Memories without embeddings should be excluded")
    }
}
