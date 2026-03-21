import Foundation

/// Retrieves the most relevant note chunks for a query via cosine similarity.
public class ChunkRetrievalService {

    public init() {}

    /// Compute cosine similarity between two vectors.
    public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    /// Retrieve the top-N most relevant chunks for a query embedding.
    public func retrieveTopChunks(
        queryEmbedding: [Float],
        candidates: [(chunk: NoteChunk, embedding: [Float])],
        limit: Int,
        minSimilarity: Float,
        tokenBudget: Int? = nil
    ) -> [(chunk: NoteChunk, similarity: Float)] {
        guard !candidates.isEmpty else { return [] }

        // Score all candidates
        var scored: [(chunk: NoteChunk, similarity: Float)] = candidates.compactMap { candidate in
            let sim = cosineSimilarity(queryEmbedding, candidate.embedding)
            guard sim >= minSimilarity else { return nil }
            return (chunk: candidate.chunk, similarity: sim)
        }

        // Sort by similarity descending
        scored.sort { $0.similarity > $1.similarity }

        // Apply limit
        var results = Array(scored.prefix(limit))

        // Apply token budget if specified
        if let budget = tokenBudget {
            var totalTokens = 0
            results = results.filter { item in
                totalTokens += item.chunk.tokenCount
                return totalTokens <= budget
            }
        }

        return results
    }
}
