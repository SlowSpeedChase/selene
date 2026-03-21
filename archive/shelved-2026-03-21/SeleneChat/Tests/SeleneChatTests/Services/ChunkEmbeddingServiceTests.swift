import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkEmbeddingServiceTests: XCTestCase {

    // MARK: - Mock Provider

    private class MockEmbeddingProvider: LLMProvider {
        var embedCallCount = 0
        var embeddedTexts: [String] = []

        func generate(prompt: String, model: String?) async throws -> String { "" }

        func embed(text: String, model: String?) async throws -> [Float] {
            embedCallCount += 1
            embeddedTexts.append(text)
            return [Float](repeating: 0.1, count: 768)
        }

        func isAvailable() async -> Bool { true }
    }

    // MARK: - Batch Embedding

    func testCreatesBatchEmbeddingRequests() async {
        let mockProvider = MockEmbeddingProvider()
        let service = ChunkEmbeddingService(embeddingProvider: mockProvider)

        let chunks = [
            NoteChunk.mock(id: 1, content: "First chunk"),
            NoteChunk.mock(id: 2, content: "Second chunk"),
            NoteChunk.mock(id: 3, content: "Third chunk"),
        ]

        let embeddings = try? await service.generateEmbeddings(for: chunks)
        XCTAssertEqual(embeddings?.count, 3)
        XCTAssertEqual(mockProvider.embedCallCount, 3)
    }

    func testEmbeddingDimensionsAreConsistent() async throws {
        let mockProvider = MockEmbeddingProvider()
        let service = ChunkEmbeddingService(embeddingProvider: mockProvider)

        let chunks = [NoteChunk.mock(id: 1, content: "Test chunk")]
        let embeddings = try await service.generateEmbeddings(for: chunks)

        XCTAssertEqual(embeddings[0].count, 768, "nomic-embed-text returns 768 dimensions")
    }

    func testEmptyChunksReturnsEmptyEmbeddings() async throws {
        let mockProvider = MockEmbeddingProvider()
        let service = ChunkEmbeddingService(embeddingProvider: mockProvider)

        let embeddings = try await service.generateEmbeddings(for: [])

        XCTAssertTrue(embeddings.isEmpty)
        XCTAssertEqual(mockProvider.embedCallCount, 0)
    }

    func testPassesChunkContentToProvider() async throws {
        let mockProvider = MockEmbeddingProvider()
        let service = ChunkEmbeddingService(embeddingProvider: mockProvider)

        let chunks = [
            NoteChunk.mock(id: 1, content: "Alpha content"),
            NoteChunk.mock(id: 2, content: "Beta content"),
        ]

        _ = try await service.generateEmbeddings(for: chunks)

        XCTAssertEqual(mockProvider.embeddedTexts, ["Alpha content", "Beta content"])
    }
}
