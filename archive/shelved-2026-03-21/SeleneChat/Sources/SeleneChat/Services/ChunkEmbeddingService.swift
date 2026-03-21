import Foundation
import SeleneShared

/// Generates embeddings for note chunks via an LLMProvider (Ollama nomic-embed-text).
class ChunkEmbeddingService {

    private let embeddingProvider: LLMProvider

    init(embeddingProvider: LLMProvider) {
        self.embeddingProvider = embeddingProvider
    }

    /// Generate embeddings for a batch of chunks.
    /// - Parameter chunks: Chunks to embed.
    /// - Returns: Array of embedding vectors, one per chunk (same order).
    func generateEmbeddings(for chunks: [NoteChunk]) async throws -> [[Float]] {
        var embeddings: [[Float]] = []
        for chunk in chunks {
            let embedding = try await embeddingProvider.embed(text: chunk.content, model: nil)
            embeddings.append(embedding)
        }
        return embeddings
    }
}
