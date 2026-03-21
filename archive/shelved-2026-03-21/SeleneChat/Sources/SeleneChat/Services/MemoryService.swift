import SeleneShared
import Foundation

/// Service for extracting and consolidating conversation memories
actor MemoryService {
    static let shared = MemoryService()

    private let ollamaService = OllamaService.shared
    private let databaseService = DatabaseService.shared

    private init() {}

    // MARK: - Types

    struct CandidateFact: Codable {
        let fact: String
        let type: String
        let confidence: Double
    }

    struct ExtractionResult: Codable {
        let facts: [CandidateFact]
    }

    enum ConsolidationAction: String, Codable {
        case ADD
        case UPDATE
        case DELETE
        case NOOP
    }

    struct ConsolidationDecision: Codable {
        let action: ConsolidationAction
        let memoryId: Int64?
        let merged: String?
        let reason: String?
    }

    // MARK: - Extraction

    /// Extract memories from a conversation exchange
    func extractMemories(
        userMessage: String,
        assistantResponse: String,
        recentMessages: [(role: String, content: String, createdAt: Date)]
    ) async throws -> [CandidateFact] {
        // Format recent messages
        let recentContext = recentMessages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")

        let prompt = """
        You are a memory extraction system for Selene, an ADHD-focused assistant.

        Given this conversation context and the latest exchange, extract any facts
        worth remembering about the user - their preferences, patterns, projects,
        or important context.

        RECENT MESSAGES:
        \(recentContext)

        CURRENT EXCHANGE:
        User: \(userMessage)
        Assistant: \(assistantResponse)

        Return ONLY valid JSON matching this exact format (no other text):
        {
          "facts": [
            {"fact": "description of fact", "type": "preference|fact|pattern|context", "confidence": 0.8}
          ]
        }

        Only extract facts that are genuinely useful for future conversations.
        Be selective, not exhaustive. If nothing worth remembering, return {"facts": []}.
        """

        let response = try await ollamaService.generate(prompt: prompt)

        // Parse JSON response - try to extract JSON from response
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.extractMemories: no valid JSON found in response")
            #endif
            return []
        }

        do {
            let result = try JSONDecoder().decode(ExtractionResult.self, from: jsonData)
            #if DEBUG
            DebugLogger.shared.log(.state, "MemoryService.extractMemories: extracted \(result.facts.count) facts")
            #endif
            return result.facts
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.extractMemories: JSON parse failed - \(error)")
            #endif
            return []
        }
    }

    /// Try to extract JSON object from a string that may contain extra text
    private func extractJSON(from text: String) -> String? {
        // Find the first { and last }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    // MARK: - Consolidation

    /// Consolidate a candidate fact with existing memories using embedding similarity
    func consolidateMemory(
        candidateFact: CandidateFact,
        sessionId: UUID,
        threadId: Int64? = nil
    ) async throws {
        // 1. Generate embedding for the candidate fact
        var factEmbedding: [Float]? = nil
        do {
            factEmbedding = try await ollamaService.embed(text: candidateFact.fact)
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.consolidate: embedding failed - \(error)")
            #endif
        }

        // 2. Find similar existing memories using embeddings (scoped to thread + global)
        var similarMemories: [ConversationMemory] = []
        if let embedding = factEmbedding {
            do {
                let allWithEmbeddings = try await databaseService.getAllMemoriesWithEmbeddings()
                let allMemories: [(memory: ConversationMemory, embedding: [Float]?)]
                if let threadId = threadId {
                    let threadMemories = try await databaseService.getMemoriesForThread(threadId: threadId, limit: 50)
                    let threadMemoryIds = Set(threadMemories.map { $0.id })
                    allMemories = allWithEmbeddings.filter { threadMemoryIds.contains($0.memory.id) }
                } else {
                    allMemories = allWithEmbeddings
                }
                let similar = MemoryService.findSimilarMemories(
                    queryEmbedding: embedding,
                    memories: allMemories,
                    threshold: 0.7,
                    limit: 10
                )
                similarMemories = similar.map { $0.memory }
            } catch {
                #if DEBUG
                DebugLogger.shared.log(.error, "MemoryService.consolidate: similarity search failed - \(error)")
                #endif
            }
        }

        // 3. If no similar memories, just ADD
        if similarMemories.isEmpty {
            let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
            _ = try await databaseService.insertMemory(
                content: candidateFact.fact,
                type: memoryType,
                confidence: candidateFact.confidence,
                sourceSessionId: sessionId,
                threadId: threadId,
                embedding: factEmbedding
            )
            #if DEBUG
            DebugLogger.shared.log(.state, "MemoryService.consolidate: ADD (no similar)")
            #endif
            return
        }

        // 4. Ask LLM to decide
        let similarStr = similarMemories.enumerated().map { (i, m) in
            "\(i + 1). [id=\(m.id)] \(m.content)"
        }.joined(separator: "\n")

        let prompt = """
        You are managing a memory system. Given a new fact and existing similar
        memories, decide what to do.

        NEW FACT: "\(candidateFact.fact)"

        EXISTING SIMILAR MEMORIES:
        \(similarStr)

        Return ONLY valid JSON matching one of these formats (no other text):
        - {"action": "ADD"} - New information, nothing equivalent exists
        - {"action": "UPDATE", "memoryId": N, "merged": "combined fact text"} - Augment existing
        - {"action": "DELETE", "memoryId": N, "reason": "why"} - New fact contradicts this
        - {"action": "NOOP", "reason": "why"} - Already known or not worth storing

        Consider: Is this genuinely new? Does it contradict something? Is it worth remembering?
        """

        let response = try await ollamaService.generate(prompt: prompt)

        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.consolidate: no valid JSON in response")
            #endif
            let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
            _ = try await databaseService.insertMemory(
                content: candidateFact.fact,
                type: memoryType,
                confidence: candidateFact.confidence,
                sourceSessionId: sessionId,
                threadId: threadId,
                embedding: factEmbedding
            )
            return
        }

        do {
            let decision = try JSONDecoder().decode(ConsolidationDecision.self, from: jsonData)

            switch decision.action {
            case .ADD:
                let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
                _ = try await databaseService.insertMemory(
                    content: candidateFact.fact,
                    type: memoryType,
                    confidence: candidateFact.confidence,
                    sourceSessionId: sessionId,
                    threadId: threadId,
                    embedding: factEmbedding
                )
                #if DEBUG
                DebugLogger.shared.log(.state, "MemoryService.consolidate: ADD")
                #endif

            case .UPDATE:
                if let memoryId = decision.memoryId, let merged = decision.merged {
                    var mergedEmbedding: [Float]? = nil
                    do {
                        mergedEmbedding = try await ollamaService.embed(text: merged)
                    } catch {
                        #if DEBUG
                        DebugLogger.shared.log(.error, "MemoryService.consolidate: re-embed failed for UPDATE")
                        #endif
                    }
                    try await databaseService.updateMemory(
                        id: memoryId,
                        content: merged,
                        embedding: mergedEmbedding
                    )
                    #if DEBUG
                    DebugLogger.shared.log(.state, "MemoryService.consolidate: UPDATE \(memoryId)")
                    #endif
                }

            case .DELETE:
                if let memoryId = decision.memoryId {
                    try await databaseService.deleteMemory(id: memoryId)
                    #if DEBUG
                    DebugLogger.shared.log(.state, "MemoryService.consolidate: DELETE \(memoryId)")
                    #endif
                }

            case .NOOP:
                #if DEBUG
                DebugLogger.shared.log(.state, "MemoryService.consolidate: NOOP - \(decision.reason ?? "no reason")")
                #endif
            }

        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.consolidate: JSON parse failed, defaulting to ADD")
            #endif
            let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
            _ = try await databaseService.insertMemory(
                content: candidateFact.fact,
                type: memoryType,
                confidence: candidateFact.confidence,
                sourceSessionId: sessionId,
                threadId: threadId,
                embedding: factEmbedding
            )
        }
    }

    // MARK: - Backfill

    /// Backfill embeddings for memories that don't have them.
    /// Returns the number of memories that were embedded.
    func backfillEmbeddings() async throws -> Int {
        let allMemories = try await databaseService.getAllMemoriesWithEmbeddings()
        let needsEmbedding = allMemories.filter { $0.embedding == nil }

        guard !needsEmbedding.isEmpty else {
            #if DEBUG
            DebugLogger.shared.log(.state, "MemoryService.backfill: all memories have embeddings")
            #endif
            return 0
        }

        #if DEBUG
        DebugLogger.shared.log(.state, "MemoryService.backfill: embedding \(needsEmbedding.count) memories")
        #endif

        var count = 0
        for item in needsEmbedding {
            do {
                let embedding = try await ollamaService.embed(text: item.memory.content)
                try await databaseService.saveMemoryEmbedding(id: item.memory.id, embedding: embedding)
                count += 1
            } catch {
                #if DEBUG
                DebugLogger.shared.log(.error, "MemoryService.backfill: failed for memory \(item.memory.id) - \(error)")
                #endif
                // Continue with other memories - don't fail the whole batch
            }
        }

        #if DEBUG
        DebugLogger.shared.log(.state, "MemoryService.backfill: completed \(count)/\(needsEmbedding.count)")
        #endif

        return count
    }

    // MARK: - Similarity Search

    /// Result of a similarity search
    struct SimilarMemory {
        let memory: ConversationMemory
        let similarity: Float
        let weightedScore: Double
    }

    /// Find memories similar to a query embedding. Pure function for testability.
    /// Ranks by similarity * confidence. Excludes memories without embeddings.
    static func findSimilarMemories(
        queryEmbedding: [Float],
        memories: [(memory: ConversationMemory, embedding: [Float]?)],
        threshold: Float,
        limit: Int
    ) -> [SimilarMemory] {
        return memories
            .compactMap { item -> SimilarMemory? in
                guard let embedding = item.embedding else { return nil }
                let similarity = cosineSimilarity(queryEmbedding, embedding)
                guard similarity >= threshold else { return nil }
                let weightedScore = Double(similarity) * item.memory.confidence
                return SimilarMemory(memory: item.memory, similarity: similarity, weightedScore: weightedScore)
            }
            .sorted { $0.weightedScore > $1.weightedScore }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Retrieval

    /// Get relevant memories for a query using embedding similarity.
    /// Falls back to keyword matching if Ollama is unavailable.
    func getRelevantMemories(for query: String, limit: Int = 5, threadId: Int64? = nil) async throws -> [ConversationMemory] {
        // Try embedding-based retrieval
        do {
            let queryEmbedding = try await ollamaService.embed(text: query)

            let allMemories: [(memory: ConversationMemory, embedding: [Float]?)]
            if let threadId = threadId {
                // Thread-scoped: get only thread + global memories, then fetch their embeddings
                let threadMemories = try await databaseService.getMemoriesForThread(threadId: threadId, limit: 50)
                let threadMemoryIds = Set(threadMemories.map { $0.id })
                let allWithEmbeddings = try await databaseService.getAllMemoriesWithEmbeddings()
                allMemories = allWithEmbeddings.filter { threadMemoryIds.contains($0.memory.id) }
            } else {
                allMemories = try await databaseService.getAllMemoriesWithEmbeddings()
            }

            let results = MemoryService.findSimilarMemories(
                queryEmbedding: queryEmbedding,
                memories: allMemories,
                threshold: 0.5,
                limit: limit
            )

            let relevant = results.map { $0.memory }

            // Touch accessed memories for reinforcement
            if !relevant.isEmpty {
                try await databaseService.touchMemories(ids: relevant.map { $0.id })
            }

            #if DEBUG
            DebugLogger.shared.log(.state, "MemoryService.getRelevant: \(relevant.count) memories via embedding search")
            #endif

            return relevant

        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.getRelevant: embedding search failed, falling back to keywords - \(error)")
            #endif

            // Fallback to keyword matching
            return try await getRelevantMemoriesByKeyword(for: query, limit: limit, threadId: threadId)
        }
    }

    /// Keyword-based fallback when Ollama is unavailable
    private func getRelevantMemoriesByKeyword(for query: String, limit: Int, threadId: Int64? = nil) async throws -> [ConversationMemory] {
        let allMemories: [ConversationMemory]
        if let threadId = threadId {
            allMemories = try await databaseService.getMemoriesForThread(threadId: threadId, limit: 50)
        } else {
            allMemories = try await databaseService.getAllMemories(limit: 50)
        }
        let queryWords = Set(query.lowercased().split(separator: " ").map(String.init))

        let scored = allMemories.map { memory -> (memory: ConversationMemory, score: Double) in
            let contentWords = Set(memory.content.lowercased().split(separator: " ").map(String.init))
            let overlap = queryWords.intersection(contentWords).count
            let score = Double(overlap) * memory.confidence
            return (memory: memory, score: score)
        }

        let relevant = scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.memory }

        if !relevant.isEmpty {
            try await databaseService.touchMemories(ids: relevant.map { $0.id })
        }

        return Array(relevant)
    }
}
