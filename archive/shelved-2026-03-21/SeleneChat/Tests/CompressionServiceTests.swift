import SeleneShared
import XCTest
import Foundation
@testable import SeleneChat

final class CompressionServiceTests: XCTestCase {
    var databaseService: DatabaseService!
    var compressionService: CompressionService!
    var testDatabasePath: String!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path

        // Initialize database service with test path
        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath

        // Initialize compression service with test database
        compressionService = CompressionService(databaseService: databaseService)
    }

    override func tearDown() async throws {
        // Clean up test database
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        compressionService = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func testCheckAndCompressSessionsIdentifiesOldSessions() async throws {
        // Create an old session that should be compressed
        let thirtyOneDaysAgo = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        let oldSession = ChatSession(
            id: UUID(),
            messages: [
                createUserMessage(content: "What is Swift?"),
                createAssistantMessage(content: "Swift is a programming language."),
                createUserMessage(content: "Tell me about async/await"),
                createAssistantMessage(content: "Async/await is a concurrency model.")
            ],
            createdAt: thirtyOneDaysAgo,
            updatedAt: thirtyOneDaysAgo,
            title: "Old Programming Session"
        )
        try await databaseService.saveSession(oldSession)

        // Create a recent session that should NOT be compressed
        let recentSession = ChatSession(
            id: UUID(),
            messages: [createUserMessage(content: "Hello")],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Recent Session"
        )
        try await databaseService.saveSession(recentSession)

        // Run compression check
        await compressionService.checkAndCompressSessions()

        // Verify the old session was compressed
        let sessions = try await databaseService.loadSessions()

        guard let compressedSession = sessions.first(where: { $0.id == oldSession.id }) else {
            XCTFail("Old session not found")
            return
        }

        XCTAssertEqual(compressedSession.compressionState, .compressed, "Old session should be compressed")
        XCTAssertNotNil(compressedSession.summaryText, "Should have summary text")
        XCTAssertNotNil(compressedSession.compressedAt, "Should have compressed timestamp")

        // Verify recent session was NOT compressed
        guard let unchangedSession = sessions.first(where: { $0.id == recentSession.id }) else {
            XCTFail("Recent session not found")
            return
        }

        XCTAssertEqual(unchangedSession.compressionState, .full, "Recent session should remain in full state")
        XCTAssertNil(unchangedSession.summaryText, "Recent session should not have summary")
    }

    func testGenerateSummaryExtractsUserQueries() async throws {
        // Create a session with multiple user messages
        let testDate = Date()
        var session = ChatSession(
            id: UUID(),
            messages: [
                createUserMessage(content: "What is SwiftUI?"),
                createAssistantMessage(content: "SwiftUI is Apple's UI framework."),
                createUserMessage(content: "How do I use @State?"),
                createAssistantMessage(content: "Use @State for simple value types."),
                createUserMessage(content: "What about @Binding?"),
                createAssistantMessage(content: "@Binding creates a two-way connection.")
            ],
            createdAt: testDate,
            updatedAt: testDate,
            title: "SwiftUI Questions"
        )

        // Generate summary using the compression service
        let summary = await compressionService.generateSummary(for: session)

        // Verify summary contains session metadata
        XCTAssertTrue(summary.contains("SwiftUI Questions"), "Summary should contain session title")
        XCTAssertTrue(summary.contains("3"), "Summary should contain question count (3 user messages)")

        // Verify summary contains user queries
        XCTAssertTrue(summary.contains("What is SwiftUI?"), "Summary should contain first user query")
        XCTAssertTrue(summary.contains("How do I use @State?"), "Summary should contain second user query")
        XCTAssertTrue(summary.contains("What about @Binding?"), "Summary should contain third user query")

        // Verify summary format (should be bullet list)
        XCTAssertTrue(summary.contains("-"), "Summary should use bullet points")
    }

    func testPinnedSessionsNotCompressed() async throws {
        // Create an old but pinned session
        let thirtyOneDaysAgo = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        var pinnedSession = ChatSession(
            id: UUID(),
            messages: [
                createUserMessage(content: "Important query"),
                createAssistantMessage(content: "Important response")
            ],
            createdAt: thirtyOneDaysAgo,
            updatedAt: thirtyOneDaysAgo,
            title: "Important Pinned Session",
            isPinned: true
        )
        try await databaseService.saveSession(pinnedSession)

        // Run compression check
        await compressionService.checkAndCompressSessions()

        // Verify the pinned session was NOT compressed
        let sessions = try await databaseService.loadSessions()

        guard let unchangedSession = sessions.first(where: { $0.id == pinnedSession.id }) else {
            XCTFail("Pinned session not found")
            return
        }

        XCTAssertEqual(unchangedSession.compressionState, .full, "Pinned session should remain in full state")
        XCTAssertNil(unchangedSession.summaryText, "Pinned session should not have summary")
        XCTAssertNil(unchangedSession.compressedAt, "Pinned session should not be compressed")
        XCTAssertTrue(unchangedSession.isPinned, "Session should still be pinned")
    }

    // MARK: - Helper Methods

    private func createUserMessage(content: String) -> Message {
        Message(
            id: UUID(),
            role: .user,
            content: content,
            timestamp: Date(),
            llmTier: .onDevice,
            relatedNotes: nil
        )
    }

    private func createAssistantMessage(content: String) -> Message {
        Message(
            id: UUID(),
            role: .assistant,
            content: content,
            timestamp: Date(),
            llmTier: .onDevice,
            relatedNotes: nil
        )
    }
}
