import Foundation

/// Protocol abstracting data access for Selene.
/// Implemented by DatabaseService (macOS, direct SQLite) and RemoteDataService (iOS, HTTP).
public protocol DataProvider: AnyObject {

    // MARK: - Notes

    func getAllNotes(limit: Int) async throws -> [Note]
    func getNote(byId noteId: Int) async throws -> Note?
    func searchNotes(query: String, limit: Int) async throws -> [Note]
    func searchNotesSemantically(query: String, limit: Int) async -> [Note]
    func getRecentNotes(days: Int, limit: Int) async throws -> [Note]
    func getNotesSince(_ date: Date, limit: Int) async throws -> [Note]
    func getRelatedNotes(for noteId: Int, limit: Int) async -> [(note: Note, relationshipType: String, strength: Double?)]
    func getThreadAssignmentsForNotes(_ noteIds: [Int]) async throws -> [Int: (threadName: String, threadId: Int64)]
    func retrieveNotesFor(queryType: QueryAnalyzer.QueryType, keywords: [String], timeScope: QueryAnalyzer.TimeScope, limit: Int) async throws -> [Note]

    /// Find notes with strong emotional signals related to keywords
    func getEmotionalNotes(keywords: [String], limit: Int) async throws -> [Note]

    /// Get emotional tone distribution over a time window
    func getSentimentTrend(days: Int) async throws -> SentimentTrend

    // MARK: - Tasks

    /// Find task outcomes related to keywords
    func getTaskOutcomes(keywords: [String], limit: Int) async throws -> [TaskOutcome]

    // MARK: - Threads

    func getActiveThreads(limit: Int) async throws -> [Thread]
    func getThreadById(_ threadId: Int64) async throws -> Thread?
    func getThreadByName(_ name: String) async throws -> (Thread, [Note])?
    func getTasksForThread(_ threadId: Int64) async throws -> [ThreadTask]

    // MARK: - Sessions

    func loadSessions() async throws -> [ChatSession]
    func saveSession(_ session: ChatSession) async throws
    func deleteSession(_ session: ChatSession) async throws
    func updateSessionPin(sessionId: UUID, isPinned: Bool) async throws
    func saveConversationMessage(sessionId: UUID, role: String, content: String) async throws
    func getRecentMessages(sessionId: UUID, limit: Int) async throws -> [(role: String, content: String, createdAt: Date)]
    func getAllRecentMessages(limit: Int) async throws -> [(sessionId: String, role: String, content: String, createdAt: Date)]

    // MARK: - Memories

    func getAllMemories(limit: Int) async throws -> [ConversationMemory]
    func insertMemory(content: String, type: ConversationMemory.MemoryType, confidence: Double, sourceSessionId: UUID?, threadId: Int64?, embedding: [Float]?) async throws -> Int64
    func updateMemory(id: Int64, content: String, confidence: Double?, embedding: [Float]?) async throws
    func deleteMemory(id: Int64) async throws
    func touchMemories(ids: [Int64]) async throws
    func getAllMemoriesWithEmbeddings(limit: Int) async throws -> [(memory: ConversationMemory, embedding: [Float]?)]
    func saveMemoryEmbedding(id: Int64, embedding: [Float]) async throws

    // MARK: - Briefing

    func getCrossThreadAssociations(minSimilarity: Double, recentDays: Int, limit: Int) async throws -> [(noteAId: Int, noteBId: Int, similarity: Double)]

    // MARK: - Availability

    func isAPIAvailable() async -> Bool
}
