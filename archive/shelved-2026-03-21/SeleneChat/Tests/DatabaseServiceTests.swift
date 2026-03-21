import SeleneShared
import XCTest
import Foundation
@testable import SeleneChat

final class ChatSessionPersistenceTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path

        // Initialize database service with test path
        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath
    }

    override func tearDown() async throws {
        // Clean up test database
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    // MARK: - Core CRUD Operations

    func testSaveAndLoadSession() async throws {
        // Create a test session with messages
        var session = ChatSession(
            id: UUID(),
            messages: [
                Message(
                    id: UUID(),
                    role: .user,
                    content: "Hello, what can you help me with?",
                    timestamp: Date(),
                    llmTier: .onDevice,
                    relatedNotes: nil
                ),
                Message(
                    id: UUID(),
                    role: .assistant,
                    content: "I can help you search your notes and answer questions about them.",
                    timestamp: Date(),
                    llmTier: .onDevice,
                    relatedNotes: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Test Session"
        )

        // Save the session
        try await databaseService.saveSession(session)

        // Load all sessions
        let loadedSessions = try await databaseService.loadSessions()

        // Verify the session was saved and loaded correctly
        XCTAssertEqual(loadedSessions.count, 1, "Should have exactly one session")

        guard let loadedSession = loadedSessions.first else {
            XCTFail("Failed to load session")
            return
        }

        XCTAssertEqual(loadedSession.id, session.id, "Session ID should match")
        XCTAssertEqual(loadedSession.title, session.title, "Session title should match")
        XCTAssertEqual(loadedSession.messages.count, session.messages.count, "Message count should match")
        XCTAssertEqual(loadedSession.isPinned, false, "Default isPinned should be false")
        XCTAssertEqual(loadedSession.compressionState, .full, "Default compression state should be full")

        // Verify messages
        XCTAssertEqual(loadedSession.messages[0].content, "Hello, what can you help me with?")
        XCTAssertEqual(loadedSession.messages[1].content, "I can help you search your notes and answer questions about them.")
    }

    // MARK: - Compression Query Tests

    func testGetSessionsReadyForCompression() async throws {
        // Create sessions with different scenarios
        let thirtyOneDaysAgo = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: Date())!

        // Scenario 1: Old session, not pinned, full state → SHOULD be returned
        let oldSession = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: thirtyOneDaysAgo,
            updatedAt: thirtyOneDaysAgo,
            title: "Old Session - Should Compress"
        )
        try await databaseService.saveSession(oldSession)

        // Scenario 2: Recent session → should NOT be returned
        let recentSession = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: twentyDaysAgo,
            updatedAt: twentyDaysAgo,
            title: "Recent Session"
        )
        try await databaseService.saveSession(recentSession)

        // Scenario 3: Old session but pinned → should NOT be returned
        var pinnedSession = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: thirtyOneDaysAgo,
            updatedAt: thirtyOneDaysAgo,
            title: "Pinned Old Session"
        )
        pinnedSession.isPinned = true
        try await databaseService.saveSession(pinnedSession)

        // Scenario 4: Old session but already compressed → should NOT be returned
        var compressedSession = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: thirtyOneDaysAgo,
            updatedAt: thirtyOneDaysAgo,
            title: "Already Compressed Session"
        )
        compressedSession.compressionState = .compressed
        compressedSession.summaryText = "Test summary"
        try await databaseService.saveSession(compressedSession)

        // Call the method (will fail until implemented)
        let sessionsToCompress = try await databaseService.getSessionsReadyForCompression()

        // Verify results
        XCTAssertEqual(sessionsToCompress.count, 1, "Should return exactly 1 session ready for compression")

        guard let sessionToCompress = sessionsToCompress.first else {
            XCTFail("No session returned")
            return
        }

        // Verify it's the correct session
        XCTAssertEqual(sessionToCompress.id, oldSession.id, "Should return the old, unpinned, full session")
        XCTAssertEqual(sessionToCompress.title, "Old Session - Should Compress")
        XCTAssertEqual(sessionToCompress.compressionState, .full)
        XCTAssertFalse(sessionToCompress.isPinned)

        // Verify created_at is > 30 days old
        let daysSinceCreation = Calendar.current.dateComponents([.day], from: sessionToCompress.createdAt, to: Date()).day ?? 0
        XCTAssertGreaterThan(daysSinceCreation, 30, "Session should be more than 30 days old")
    }

    func testCompressSession() async throws {
        // Create a test session with full messages
        let session = ChatSession(
            id: UUID(),
            messages: [
                createTestMessage(),
                Message(
                    id: UUID(),
                    role: .user,
                    content: "What are my notes about Swift?",
                    timestamp: Date(),
                    llmTier: .onDevice,
                    relatedNotes: nil
                ),
                Message(
                    id: UUID(),
                    role: .assistant,
                    content: "Here are your Swift notes...",
                    timestamp: Date(),
                    llmTier: .onDevice,
                    relatedNotes: [1, 2, 3]
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Session to Compress"
        )

        // Save the session
        try await databaseService.saveSession(session)

        // Verify it's in 'full' state with messages
        let loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1)
        XCTAssertEqual(loadedSessions[0].compressionState, .full)
        XCTAssertEqual(loadedSessions[0].messages.count, 3)
        XCTAssertNil(loadedSessions[0].summaryText)
        XCTAssertNil(loadedSessions[0].compressedAt)

        // Compress the session
        let summary = """
        Session: Session to Compress
        Questions asked: 2
        Key queries:
        - Test message
        - What are my notes about Swift?
        """
        try await databaseService.compressSession(sessionId: session.id, summary: summary)

        // Load and verify compression worked
        let compressedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(compressedSessions.count, 1)

        let compressedSession = compressedSessions[0]
        XCTAssertEqual(compressedSession.id, session.id)
        XCTAssertEqual(compressedSession.compressionState, .compressed, "Should be in compressed state")
        XCTAssertEqual(compressedSession.summaryText, summary, "Summary should match")
        XCTAssertNotNil(compressedSession.compressedAt, "compressed_at should be set")
        XCTAssertEqual(compressedSession.messages.count, 0, "Full messages should be cleared")

        // Verify compressed_at timestamp is recent (within last minute)
        let timeSinceCompression = Date().timeIntervalSince(compressedSession.compressedAt!)
        XCTAssertLessThan(timeSinceCompression, 60, "compressed_at should be recent")
    }

    func testUpdateCompressionState() async throws {
        // Create a test session in 'full' state
        let session = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: Date(),
            updatedAt: Date(),
            title: "State Transition Test"
        )
        try await databaseService.saveSession(session)

        // Verify initial state is 'full'
        var loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions[0].compressionState, .full)

        // Transition to 'processing' state
        try await databaseService.updateCompressionState(sessionId: session.id, state: .processing)

        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions[0].compressionState, .processing, "Should transition to processing state")

        // Transition to 'compressed' state
        try await databaseService.updateCompressionState(sessionId: session.id, state: .compressed)

        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions[0].compressionState, .compressed, "Should transition to compressed state")

        // Verify we can go back to 'full' if needed (edge case)
        try await databaseService.updateCompressionState(sessionId: session.id, state: .full)

        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions[0].compressionState, .full, "Should allow transition back to full")
    }

    func testUpdateSessionPin() async throws {
        // Create a test session (default isPinned = false)
        let session = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Pin Test Session"
        )
        try await databaseService.saveSession(session)

        // Verify initial pin state is false
        var loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1)
        XCTAssertFalse(loadedSessions[0].isPinned, "Default isPinned should be false")

        // Pin the session
        try await databaseService.updateSessionPin(sessionId: session.id, isPinned: true)

        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1)
        XCTAssertTrue(loadedSessions[0].isPinned, "Session should be pinned")

        // Unpin the session
        try await databaseService.updateSessionPin(sessionId: session.id, isPinned: false)

        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1)
        XCTAssertFalse(loadedSessions[0].isPinned, "Session should be unpinned")
    }

    func testDeleteSession() async throws {
        // Create two test sessions
        let session1 = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Session to Keep"
        )
        let session2 = ChatSession(
            id: UUID(),
            messages: [createTestMessage()],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Session to Delete"
        )

        try await databaseService.saveSession(session1)
        try await databaseService.saveSession(session2)

        // Verify both sessions exist
        var loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 2, "Should have 2 sessions")

        // Delete session2
        try await databaseService.deleteSession(session2)

        // Verify only session1 remains
        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1, "Should have 1 session after deletion")
        XCTAssertEqual(loadedSessions[0].id, session1.id, "Remaining session should be session1")
        XCTAssertEqual(loadedSessions[0].title, "Session to Keep")

        // Delete session1
        try await databaseService.deleteSession(session1)

        // Verify no sessions remain
        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 0, "Should have 0 sessions after deleting all")
    }

    func testSaveEmptySession() async throws {
        // Create a session with zero messages
        let emptySession = ChatSession(
            id: UUID(),
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            title: "Empty Session"
        )

        // Save the empty session
        try await databaseService.saveSession(emptySession)

        // Load and verify
        let loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1, "Should save empty session")

        guard let loadedSession = loadedSessions.first else {
            XCTFail("Failed to load empty session")
            return
        }

        XCTAssertEqual(loadedSession.id, emptySession.id)
        XCTAssertEqual(loadedSession.title, "Empty Session")
        XCTAssertEqual(loadedSession.messages.count, 0, "Should have zero messages")
        XCTAssertEqual(loadedSession.compressionState, .full, "Empty session should be in full state")
    }

    func testSessionWithNoUserMessages() async throws {
        // Create a session with only assistant messages (edge case)
        let thirtyOneDaysAgo = Calendar.current.date(byAdding: .day, value: -31, to: Date())!

        let assistantOnlySession = ChatSession(
            id: UUID(),
            messages: [
                Message(
                    id: UUID(),
                    role: .assistant,
                    content: "Hello! How can I help you?",
                    timestamp: Date(),
                    llmTier: .onDevice,
                    relatedNotes: nil
                ),
                Message(
                    id: UUID(),
                    role: .assistant,
                    content: "I'm here to assist with your notes.",
                    timestamp: Date(),
                    llmTier: .onDevice,
                    relatedNotes: nil
                )
            ],
            createdAt: thirtyOneDaysAgo,
            updatedAt: thirtyOneDaysAgo,
            title: "Assistant-Only Session"
        )

        // Save the session
        try await databaseService.saveSession(assistantOnlySession)

        // Verify it can be loaded
        var loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1)
        XCTAssertEqual(loadedSessions[0].messages.count, 2)
        XCTAssertEqual(loadedSessions[0].messages[0].role, .assistant)
        XCTAssertEqual(loadedSessions[0].messages[1].role, .assistant)

        // Verify it appears in compression candidates (old, unpinned, full state)
        let compressionCandidates = try await databaseService.getSessionsReadyForCompression()
        XCTAssertEqual(compressionCandidates.count, 1, "Assistant-only session should be eligible for compression")
        XCTAssertEqual(compressionCandidates[0].id, assistantOnlySession.id)

        // Compress the assistant-only session
        let summary = "Session with only assistant messages. No user queries recorded."
        try await databaseService.compressSession(sessionId: assistantOnlySession.id, summary: summary)

        // Verify compression worked
        loadedSessions = try await databaseService.loadSessions()
        XCTAssertEqual(loadedSessions.count, 1)
        XCTAssertEqual(loadedSessions[0].compressionState, .compressed)
        XCTAssertEqual(loadedSessions[0].summaryText, summary)
        XCTAssertEqual(loadedSessions[0].messages.count, 0, "Messages should be cleared after compression")
    }

    // MARK: - Helper Methods

    private func createTestMessage() -> Message {
        Message(
            id: UUID(),
            role: .user,
            content: "Test message",
            timestamp: Date(),
            llmTier: .onDevice,
            relatedNotes: nil
        )
    }
}
