import XCTest
import SeleneShared
@testable import SeleneChat

// MARK: - Mock DataProvider

private class MockDataProvider: DataProvider {

    // Settable return values for methods under test
    var emotionalNotes: [Note] = []
    var taskOutcomes: [TaskOutcome] = []
    var sentimentTrendResult = SentimentTrend(toneCounts: [:], totalNotes: 0, averageSentimentScore: nil, periodDays: 7)
    var threadById: SeleneShared.Thread?
    var threadTasks: [ThreadTask] = []

    // MARK: - Notes

    func getAllNotes(limit: Int) async throws -> [Note] { [] }
    func getNote(byId noteId: Int) async throws -> Note? { nil }
    func searchNotes(query: String, limit: Int) async throws -> [Note] { [] }
    func searchNotesSemantically(query: String, limit: Int) async -> [Note] { [] }
    func getRecentNotes(days: Int, limit: Int) async throws -> [Note] { [] }
    func getNotesSince(_ date: Date, limit: Int) async throws -> [Note] { [] }
    func getRelatedNotes(for noteId: Int, limit: Int) async -> [(note: Note, relationshipType: String, strength: Double?)] { [] }
    func getThreadAssignmentsForNotes(_ noteIds: [Int]) async throws -> [Int: (threadName: String, threadId: Int64)] { [:] }
    func retrieveNotesFor(queryType: QueryAnalyzer.QueryType, keywords: [String], timeScope: QueryAnalyzer.TimeScope, limit: Int) async throws -> [Note] { [] }

    func getEmotionalNotes(keywords: [String], limit: Int) async throws -> [Note] {
        Array(emotionalNotes.prefix(limit))
    }

    func getSentimentTrend(days: Int) async throws -> SentimentTrend {
        sentimentTrendResult
    }

    // MARK: - Tasks

    func getTaskOutcomes(keywords: [String], limit: Int) async throws -> [TaskOutcome] {
        Array(taskOutcomes.prefix(limit))
    }

    // MARK: - Threads

    func getActiveThreads(limit: Int) async throws -> [SeleneShared.Thread] { [] }

    func getThreadById(_ threadId: Int64) async throws -> SeleneShared.Thread? {
        threadById
    }

    func getThreadByName(_ name: String) async throws -> (SeleneShared.Thread, [Note])? { nil }

    func getTasksForThread(_ threadId: Int64) async throws -> [ThreadTask] {
        threadTasks
    }

    // MARK: - Sessions

    func loadSessions() async throws -> [ChatSession] { [] }
    func saveSession(_ session: ChatSession) async throws {}
    func deleteSession(_ session: ChatSession) async throws {}
    func updateSessionPin(sessionId: UUID, isPinned: Bool) async throws {}
    func saveConversationMessage(sessionId: UUID, role: String, content: String) async throws {}
    func getRecentMessages(sessionId: UUID, limit: Int) async throws -> [(role: String, content: String, createdAt: Date)] { [] }
    func getAllRecentMessages(limit: Int) async throws -> [(sessionId: String, role: String, content: String, createdAt: Date)] { [] }

    // MARK: - Memories

    func getAllMemories(limit: Int) async throws -> [ConversationMemory] { [] }
    func insertMemory(content: String, type: ConversationMemory.MemoryType, confidence: Double, sourceSessionId: UUID?, threadId: Int64? = nil, embedding: [Float]?) async throws -> Int64 { 0 }
    func updateMemory(id: Int64, content: String, confidence: Double?, embedding: [Float]?) async throws {}
    func deleteMemory(id: Int64) async throws {}
    func touchMemories(ids: [Int64]) async throws {}
    func getAllMemoriesWithEmbeddings(limit: Int) async throws -> [(memory: ConversationMemory, embedding: [Float]?)] { [] }
    func saveMemoryEmbedding(id: Int64, embedding: [Float]) async throws {}

    // MARK: - Briefing

    func getCrossThreadAssociations(minSimilarity: Double, recentDays: Int, limit: Int) async throws -> [(noteAId: Int, noteBId: Int, similarity: Double)] { [] }

    // MARK: - Availability

    func isAPIAvailable() async -> Bool { true }
}

// MARK: - Tests

@MainActor
final class ContextualRetrieverTests: XCTestCase {

    func testRetrieveReturnsEmotionalHistoryBlocks() async throws {
        let mock = MockDataProvider()
        mock.emotionalNotes = [
            Note.mock(id: 1, title: "Morning frustration",
                      content: "I keep failing at morning routines",
                      createdAt: Date(), emotionalTone: "frustrated")
        ]
        let retriever = ContextualRetriever(dataProvider: mock)
        let context = try await retriever.retrieve(query: "morning routines", keywords: ["morning"])

        XCTAssertTrue(context.blocks.contains { $0.type == .emotionalHistory })
        XCTAssertTrue(context.formatted().contains("[EMOTIONAL HISTORY"))
    }

    func testRetrieveReturnsTaskHistoryBlock() async throws {
        let mock = MockDataProvider()
        mock.taskOutcomes = [
            TaskOutcome(taskTitle: "Wake up early", taskType: "action",
                       energyRequired: "high", estimatedMinutes: 15,
                       status: "abandoned", createdAt: Date(),
                       completedAt: nil, daysOpen: 12)
        ]
        let retriever = ContextualRetriever(dataProvider: mock)
        let context = try await retriever.retrieve(query: "morning", keywords: ["morning"])

        XCTAssertTrue(context.blocks.contains { $0.type == .taskHistory })
        XCTAssertTrue(context.formatted().contains("Wake up early"))
    }

    func testRetrieveReturnsSentimentTrendBlock() async throws {
        let mock = MockDataProvider()
        mock.sentimentTrendResult = SentimentTrend(
            toneCounts: ["frustrated": 3, "anxious": 1],
            totalNotes: 10, averageSentimentScore: -0.3, periodDays: 7
        )
        let retriever = ContextualRetriever(dataProvider: mock)
        let context = try await retriever.retrieve(query: "test", keywords: ["test"])

        XCTAssertTrue(context.blocks.contains { $0.type == .sentimentTrend })
        XCTAssertTrue(context.formatted().contains("frustrated 3x"))
    }

    func testRetrieveReturnsThreadStateBlock() async throws {
        let mock = MockDataProvider()
        mock.threadById = SeleneShared.Thread.mock(id: 1, name: "Morning Routine",
                                       status: "active", noteCount: 8,
                                       momentumScore: 0.7, lastActivityAt: Date())
        mock.threadTasks = [ThreadTask.mock(completedAt: nil)]
        let retriever = ContextualRetriever(dataProvider: mock)
        let context = try await retriever.retrieve(query: "test", keywords: ["test"], threadId: 1)

        XCTAssertTrue(context.blocks.contains { $0.type == .threadState })
        XCTAssertTrue(context.formatted().contains("Morning Routine"))
    }

    func testRetrieveRespectsTokenBudget() async throws {
        let mock = MockDataProvider()
        // Fill with lots of emotional notes
        mock.emotionalNotes = (1...20).map { i in
            Note.mock(id: i, title: "Note \(i)",
                      content: String(repeating: "x", count: 500),
                      createdAt: Date(), emotionalTone: "frustrated")
        }
        let retriever = ContextualRetriever(dataProvider: mock, tokenBudget: 200)
        let context = try await retriever.retrieve(query: "test", keywords: ["test"])

        // Should have stopped before using all 20 notes (limit is 3 from retriever, but budget is tiny)
        let emotionalBlocks = context.blocks.filter { $0.type == .emotionalHistory }
        XCTAssertLessThan(emotionalBlocks.count, 20)
    }

    func testContextBlockFormatIncludesDateAndTitle() {
        let block = ContextBlock(
            type: .emotionalHistory,
            content: "Felt frustrated",
            sourceDate: Date(),
            sourceTitle: "Morning thoughts"
        )
        let formatted = block.formatted
        XCTAssertTrue(formatted.hasPrefix("[EMOTIONAL HISTORY"))
        XCTAssertTrue(formatted.contains("Morning thoughts"))
        XCTAssertTrue(formatted.contains("Felt frustrated"))
    }

    func testEmptyKeywordsReturnsMinimalContext() async throws {
        let mock = MockDataProvider()
        mock.sentimentTrendResult = SentimentTrend(
            toneCounts: ["calm": 5], totalNotes: 5,
            averageSentimentScore: 0.2, periodDays: 7
        )
        let retriever = ContextualRetriever(dataProvider: mock)
        let context = try await retriever.retrieve(query: "hello", keywords: [])

        // Empty keywords -> no emotional notes or task outcomes, but sentiment trend should still appear
        XCTAssertFalse(context.blocks.contains { $0.type == .emotionalHistory })
        XCTAssertTrue(context.blocks.contains { $0.type == .sentimentTrend })
    }
}
