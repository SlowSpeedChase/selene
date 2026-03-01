import Foundation
import SeleneShared

actor RemoteDataService: DataProvider {
    let baseURL: String
    let token: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - HTTP Helpers

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw RemoteServiceError.invalidURL(path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw RemoteServiceError.httpError(http.statusCode)
        }
        return data
    }

    private func get(_ path: String) async throws -> Data {
        try await request("GET", path: path)
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        return try await request("POST", path: path, body: data)
    }

    private func put(_ path: String, body: Data) async throws -> Data {
        try await request("PUT", path: path, body: body)
    }

    private func delete(_ path: String) async throws -> Data {
        try await request("DELETE", path: path)
    }

    // MARK: - Notes

    func getAllNotes(limit: Int) async throws -> [Note] {
        let data = try await get("/api/notes?limit=\(limit)")
        let response = try decoder.decode(NotesResponse.self, from: data)
        return response.notes
    }

    func getNote(byId noteId: Int) async throws -> Note? {
        do {
            let data = try await get("/api/notes/\(noteId)")
            return try decoder.decode(NoteWrapper.self, from: data).note
        } catch RemoteServiceError.httpError(404) {
            return nil
        }
    }

    func searchNotes(query: String, limit: Int) async throws -> [Note] {
        struct Body: Encodable { let query: String; let limit: Int }
        let data = try await post("/api/notes/search", body: Body(query: query, limit: limit))
        let response = try decoder.decode(NotesResponse.self, from: data)
        return response.notes
    }

    func searchNotesSemantically(query: String, limit: Int) async -> [Note] {
        do {
            struct Body: Encodable { let query: String; let limit: Int }
            let data = try await post("/api/notes/retrieve", body: Body(query: query, limit: limit))
            let response = try decoder.decode(NotesResponse.self, from: data)
            return response.notes
        } catch {
            return []
        }
    }

    func getRecentNotes(days: Int, limit: Int) async throws -> [Note] {
        let data = try await get("/api/notes/recent?days=\(days)&limit=\(limit)")
        let response = try decoder.decode(NotesResponse.self, from: data)
        return response.notes
    }

    func getNotesSince(_ date: Date, limit: Int) async throws -> [Note] {
        let formatter = ISO8601DateFormatter()
        let dateStr = formatter.string(from: date)
        let encoded = dateStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dateStr
        let data = try await get("/api/notes/since/\(encoded)?limit=\(limit)")
        let response = try decoder.decode(NotesResponse.self, from: data)
        return response.notes
    }

    func getRelatedNotes(for noteId: Int, limit: Int) async -> [(note: Note, relationshipType: String, strength: Double?)] {
        do {
            let data = try await get("/api/notes/\(noteId)/related?limit=\(limit)")
            let response = try decoder.decode(RelatedNotesResponse.self, from: data)
            return response.results.map { ($0.note, $0.relationshipType, $0.strength) }
        } catch {
            return []
        }
    }

    func getThreadAssignmentsForNotes(_ noteIds: [Int]) async throws -> [Int: (threadName: String, threadId: Int64)] {
        struct Body: Encodable { let noteIds: [Int] }
        let data = try await post("/api/notes/thread-assignments", body: Body(noteIds: noteIds))
        let response = try decoder.decode(ThreadAssignmentsResponse.self, from: data)
        var result: [Int: (threadName: String, threadId: Int64)] = [:]
        for item in response.assignments {
            result[item.noteId] = (item.threadName, Int64(item.threadId))
        }
        return result
    }

    func getEmotionalNotes(keywords: [String], limit: Int) async throws -> [Note] {
        return []
    }

    func getSentimentTrend(days: Int) async throws -> SentimentTrend {
        return SentimentTrend(toneCounts: [:], totalNotes: 0, averageSentimentScore: nil, periodDays: days)
    }

    func getTaskOutcomes(keywords: [String], limit: Int) async throws -> [TaskOutcome] {
        return []
    }

    func retrieveNotesFor(queryType: QueryAnalyzer.QueryType, keywords: [String], timeScope: QueryAnalyzer.TimeScope, limit: Int) async throws -> [Note] {
        switch queryType {
        case .pattern, .general:
            let days: Int
            if case .recent = timeScope { days = 7 } else { days = 30 }
            return try await getRecentNotes(days: days, limit: limit)
        case .search:
            let query = keywords.joined(separator: " ")
            return try await searchNotes(query: query, limit: limit)
        case .knowledge:
            let query = keywords.joined(separator: " ")
            let keywordResults = try await searchNotes(query: query, limit: limit / 2)
            let recentResults = try await getRecentNotes(days: 7, limit: limit / 3)
            let combined = Array(Set(keywordResults + recentResults))
            return Array(combined.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        case .thread:
            let query = keywords.joined(separator: " ")
            let keywordResults = try await searchNotes(query: query, limit: limit / 2)
            let recentResults = try await getRecentNotes(days: 7, limit: limit / 2)
            let combined = Array(Set(keywordResults + recentResults))
            return Array(combined.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        case .semantic:
            let query = keywords.joined(separator: " ")
            return await searchNotesSemantically(query: query, limit: limit)
        case .deepDive, .synthesis:
            let query = keywords.joined(separator: " ")
            return try await searchNotes(query: query, limit: limit)
        }
    }

    // MARK: - Threads

    func getActiveThreads(limit: Int) async throws -> [SeleneShared.Thread] {
        let data = try await get("/api/threads?limit=\(limit)")
        let response = try decoder.decode(ThreadsListResponse.self, from: data)
        return response.threads.map { $0.toThread() }
    }

    func getThreadById(_ threadId: Int64) async throws -> SeleneShared.Thread? {
        do {
            let data = try await get("/api/threads/\(threadId)")
            let dto = try decoder.decode(ThreadDTO.self, from: data)
            return dto.toThread()
        } catch RemoteServiceError.httpError(404) {
            return nil
        }
    }

    func getThreadByName(_ name: String) async throws -> (SeleneShared.Thread, [Note])? {
        do {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            let data = try await get("/api/threads/search/\(encoded)")
            let response = try decoder.decode(ThreadWithNotesResponse.self, from: data)
            return (response.thread.toThread(), response.notes)
        } catch RemoteServiceError.httpError(404) {
            return nil
        }
    }

    func getTasksForThread(_ threadId: Int64) async throws -> [ThreadTask] {
        let data = try await get("/api/threads/\(threadId)/tasks")
        let response = try decoder.decode(ThreadTasksListResponse.self, from: data)
        return response.tasks.map { $0.toThreadTask() }
    }

    // MARK: - Sessions

    func loadSessions() async throws -> [ChatSession] {
        let data = try await get("/api/sessions")
        let response = try decoder.decode(SessionsResponse.self, from: data)
        return response.sessions
    }

    func saveSession(_ session: ChatSession) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(session)
        _ = try await put("/api/sessions/\(session.id.uuidString)", body: body)
    }

    func deleteSession(_ session: ChatSession) async throws {
        _ = try await delete("/api/sessions/\(session.id.uuidString)")
    }

    func updateSessionPin(sessionId: UUID, isPinned: Bool) async throws {
        struct Body: Encodable { let isPinned: Bool }
        let body = try JSONEncoder().encode(Body(isPinned: isPinned))
        _ = try await request("PATCH", path: "/api/sessions/\(sessionId.uuidString)/pin", body: body)
    }

    func saveConversationMessage(sessionId: UUID, role: String, content: String) async throws {
        struct Body: Encodable { let role: String; let content: String }
        _ = try await post("/api/sessions/\(sessionId.uuidString)/messages", body: Body(role: role, content: content))
    }

    func getRecentMessages(sessionId: UUID, limit: Int) async throws -> [(role: String, content: String, createdAt: Date)] {
        let data = try await get("/api/sessions/\(sessionId.uuidString)/messages?limit=\(limit)")
        let response = try decoder.decode(MessagesListResponse.self, from: data)
        return response.messages.map { ($0.role, $0.content, $0.createdAt) }
    }

    func getAllRecentMessages(limit: Int) async throws -> [(sessionId: String, role: String, content: String, createdAt: Date)] {
        // Not implemented on server yet - return empty
        return []
    }

    // MARK: - Memories

    func getAllMemories(limit: Int) async throws -> [ConversationMemory] {
        let data = try await get("/api/memories?limit=\(limit)")
        let response = try decoder.decode(MemoriesResponse.self, from: data)
        return response.memories
    }

    func insertMemory(content: String, type: ConversationMemory.MemoryType, confidence: Double, sourceSessionId: UUID?, threadId: Int64? = nil, embedding: [Float]?) async throws -> Int64 {
        struct Body: Encodable {
            let content: String; let type: String; let confidence: Double
            let sourceSessionId: String?; let threadId: Int64?
        }
        let body = Body(content: content, type: type.rawValue, confidence: confidence,
                       sourceSessionId: sourceSessionId?.uuidString, threadId: threadId)
        let data = try await post("/api/memories", body: body)
        let response = try decoder.decode(CreateIdResponse.self, from: data)
        return Int64(response.id)
    }

    func updateMemory(id: Int64, content: String, confidence: Double?, embedding: [Float]?) async throws {
        struct Body: Encodable { let content: String; let confidence: Double? }
        let body = try JSONEncoder().encode(Body(content: content, confidence: confidence))
        _ = try await request("PUT", path: "/api/memories/\(id)", body: body)
    }

    func deleteMemory(id: Int64) async throws {
        _ = try await delete("/api/memories/\(id)")
    }

    func touchMemories(ids: [Int64]) async throws {
        struct Body: Encodable { let ids: [Int64] }
        _ = try await post("/api/memories/touch", body: Body(ids: ids))
    }

    func getAllMemoriesWithEmbeddings(limit: Int) async throws -> [(memory: ConversationMemory, embedding: [Float]?)] {
        let memories = try await getAllMemories(limit: limit)
        return memories.map { ($0, nil) }
    }

    func saveMemoryEmbedding(id: Int64, embedding: [Float]) async throws {
        // Embeddings are managed server-side, no-op on iOS
    }

    // MARK: - Briefing

    func getCrossThreadAssociations(minSimilarity: Double, recentDays: Int, limit: Int) async throws -> [(noteAId: Int, noteBId: Int, similarity: Double)] {
        let data = try await get("/api/briefing/associations?minSimilarity=\(minSimilarity)&recentDays=\(recentDays)&limit=\(limit)")
        let response = try decoder.decode(AssociationsListResponse.self, from: data)
        return response.associations.map { ($0.noteAId, $0.noteBId, $0.similarity) }
    }

    // MARK: - Availability

    func isAPIAvailable() async -> Bool {
        do {
            _ = try await get("/health")
            return true
        } catch {
            return false
        }
    }

    func connectionError() async -> String? {
        do {
            _ = try await get("/health")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Response Types

private struct NotesResponse: Codable { let count: Int; let notes: [Note] }
private struct NoteWrapper: Codable { let note: Note }
private struct SessionsResponse: Codable { let count: Int; let sessions: [ChatSession] }
private struct MemoriesResponse: Codable { let count: Int; let memories: [ConversationMemory] }
private struct CreateIdResponse: Codable { let id: Int }

private struct MessagesListResponse: Codable {
    struct Item: Codable { let role: String; let content: String; let createdAt: Date }
    let messages: [Item]
}

private struct AssociationsListResponse: Codable {
    struct Item: Codable { let noteAId: Int; let noteBId: Int; let similarity: Double }
    let associations: [Item]
}

private struct RelatedNotesResponse: Codable {
    struct Item: Codable { let note: Note; let relationshipType: String; let strength: Double? }
    let results: [Item]
}

private struct ThreadAssignmentsResponse: Codable {
    struct Item: Codable { let noteId: Int; let threadName: String; let threadId: Int }
    let assignments: [Item]
}

// MARK: - Thread DTOs (Thread/ThreadTask are not Codable in SeleneShared)

private struct ThreadDTO: Codable {
    let id: Int64
    let name: String
    let why: String?
    let summary: String?
    let status: String
    let noteCount: Int
    let momentumScore: Double?
    let lastActivityAt: Date?
    let createdAt: Date
    let threadDigest: String?
    let emotionalCharge: String?

    enum CodingKeys: String, CodingKey {
        case id, name, why, summary, status
        case noteCount = "note_count"
        case momentumScore = "momentum_score"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
        case threadDigest = "thread_digest"
        case emotionalCharge = "emotional_charge"
    }

    func toThread() -> SeleneShared.Thread {
        SeleneShared.Thread(
            id: id,
            name: name,
            why: why,
            summary: summary,
            status: status,
            noteCount: noteCount,
            momentumScore: momentumScore,
            lastActivityAt: lastActivityAt,
            createdAt: createdAt,
            threadDigest: threadDigest,
            emotionalCharge: emotionalCharge
        )
    }
}

private struct ThreadsListResponse: Codable {
    let count: Int
    let threads: [ThreadDTO]
}

private struct ThreadWithNotesResponse: Codable {
    let thread: ThreadDTO
    let notes: [Note]
}

private struct ThreadTaskDTO: Codable {
    let id: Int64
    let threadId: Int64
    let thingsTaskId: String
    let createdAt: Date
    let completedAt: Date?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case thingsTaskId = "things_task_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case title
    }

    func toThreadTask() -> ThreadTask {
        ThreadTask(
            id: id,
            threadId: threadId,
            thingsTaskId: thingsTaskId,
            createdAt: createdAt,
            completedAt: completedAt,
            title: title
        )
    }
}

private struct ThreadTasksListResponse: Codable {
    let threadId: Int
    let count: Int
    let tasks: [ThreadTaskDTO]

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case count, tasks
    }
}
