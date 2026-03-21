import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkRetrievalServiceTests: XCTestCase {

    let service = ChunkRetrievalService()

    // MARK: - Cosine Similarity

    func testCosineSimilarityIdenticalVectors() {
        let v = [Float](repeating: 1.0, count: 5)
        let similarity = service.cosineSimilarity(v, v)
        XCTAssertEqual(similarity, 1.0, accuracy: 0.001)
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let similarity = service.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.001)
    }

    // MARK: - Top-N Retrieval

    func testRetrievesTopNByRelevance() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = [
            (NoteChunk.mock(id: 1, content: "Irrelevant"), [0.0, 1.0, 0.0]),   // orthogonal
            (NoteChunk.mock(id: 2, content: "Relevant"), [0.9, 0.1, 0.0]),     // very similar
            (NoteChunk.mock(id: 3, content: "Somewhat"), [0.5, 0.5, 0.0]),     // moderate
        ]

        let results = service.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 2,
            minSimilarity: 0.0
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].chunk.id, 2, "Most similar chunk should be first")
        XCTAssertEqual(results[1].chunk.id, 3, "Second most similar should be second")
    }

    func testMinSimilarityFiltersLowScores() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = [
            (NoteChunk.mock(id: 1, content: "Irrelevant"), [0.0, 1.0, 0.0]),
            (NoteChunk.mock(id: 2, content: "Relevant"), [0.9, 0.1, 0.0]),
        ]

        let results = service.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 10,
            minSimilarity: 0.5
        )

        XCTAssertEqual(results.count, 1, "Only chunks above threshold should be returned")
        XCTAssertEqual(results[0].chunk.id, 2)
    }

    // MARK: - Token Budget

    func testRespectsTokenBudget() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]
        let similarEmbedding: [Float] = [0.99, 0.01, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = (1...20).map { i in
            (NoteChunk.mock(id: Int64(i), content: String(repeating: "word ", count: 50), tokenCount: 50), similarEmbedding)
        }

        let results = service.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 20,
            minSimilarity: 0.0,
            tokenBudget: 200
        )

        let totalTokens = results.reduce(0) { $0 + $1.chunk.tokenCount }
        XCTAssertLessThanOrEqual(totalTokens, 200, "Should respect token budget")
        XCTAssertEqual(results.count, 4, "200 budget / 50 tokens = 4 chunks max")
    }

    // MARK: - Empty Input

    func testEmptyCandidatesReturnsEmpty() {
        let results = service.retrieveTopChunks(
            queryEmbedding: [1.0, 0.0],
            candidates: [],
            limit: 10,
            minSimilarity: 0.0
        )
        XCTAssertTrue(results.isEmpty)
    }
}
