import SeleneShared
import XCTest
import Foundation
@testable import SeleneChat

final class ConversationMemoryTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_memory_\(UUID().uuidString).db").path

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

    // MARK: - Conversation Storage Tests

    func testSaveConversationMessage() async throws {
        let sessionId = UUID()

        // Save a user message
        try await databaseService.saveConversationMessage(
            sessionId: sessionId,
            role: "user",
            content: "What projects am I working on?"
        )

        // Save an assistant response
        try await databaseService.saveConversationMessage(
            sessionId: sessionId,
            role: "assistant",
            content: "Based on your notes, you're working on Selene and SeleneChat."
        )

        // Retrieve recent messages
        let messages = try await databaseService.getRecentMessages(sessionId: sessionId, limit: 10)

        XCTAssertEqual(messages.count, 2, "Should have 2 messages")

        let roles = Set(messages.map(\.role))
        XCTAssertTrue(roles.contains("user"), "Should contain user message")
        XCTAssertTrue(roles.contains("assistant"), "Should contain assistant message")

        let userMsg = messages.first { $0.role == "user" }
        XCTAssertEqual(userMsg?.content, "What projects am I working on?")
    }

    func testGetRecentMessagesLimit() async throws {
        let sessionId = UUID()

        // Save 5 messages
        for i in 1...5 {
            try await databaseService.saveConversationMessage(
                sessionId: sessionId,
                role: i % 2 == 1 ? "user" : "assistant",
                content: "Message \(i)"
            )
        }

        // Request only 3 messages
        let messages = try await databaseService.getRecentMessages(sessionId: sessionId, limit: 3)

        XCTAssertEqual(messages.count, 3, "Should return only 3 messages")

        // Verify all returned messages have valid content
        for message in messages {
            XCTAssertTrue(message.content.hasPrefix("Message "), "Each message should have valid content")
        }
    }

    func testGetAllRecentMessages() async throws {
        let session1 = UUID()
        let session2 = UUID()

        // Save messages to different sessions
        try await databaseService.saveConversationMessage(sessionId: session1, role: "user", content: "Session 1 message")
        try await databaseService.saveConversationMessage(sessionId: session2, role: "user", content: "Session 2 message")

        // Get all recent messages across sessions
        let allMessages = try await databaseService.getAllRecentMessages(limit: 10)

        XCTAssertEqual(allMessages.count, 2, "Should have messages from both sessions")
    }

    // MARK: - Memory Storage Tests

    func testInsertMemory() async throws {
        let sessionId = UUID()

        // Insert a preference memory
        let memoryId = try await databaseService.insertMemory(
            content: "User prefers dark mode",
            type: .preference,
            confidence: 0.9,
            sourceSessionId: sessionId
        )

        XCTAssertGreaterThan(memoryId, 0, "Should return valid memory ID")

        // Retrieve memories
        let memories = try await databaseService.getAllMemories(limit: 10)

        XCTAssertEqual(memories.count, 1, "Should have 1 memory")
        XCTAssertEqual(memories[0].content, "User prefers dark mode")
        XCTAssertEqual(memories[0].memoryType, .preference)
        XCTAssertEqual(memories[0].confidence, 0.9, accuracy: 0.01)
    }

    func testInsertMemoryWithEmbedding() async throws {
        let sessionId = UUID()
        let testEmbedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Insert memory with embedding
        let memoryId = try await databaseService.insertMemory(
            content: "User is working on Selene project",
            type: .fact,
            confidence: 0.85,
            sourceSessionId: sessionId,
            embedding: testEmbedding
        )

        XCTAssertGreaterThan(memoryId, 0, "Should return valid memory ID")

        // Verify memory was stored (embedding storage is internal)
        let memories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].memoryType, .fact)
    }

    func testUpdateMemory() async throws {
        let sessionId = UUID()

        // Insert initial memory
        let memoryId = try await databaseService.insertMemory(
            content: "User likes coffee",
            type: .preference,
            confidence: 0.7,
            sourceSessionId: sessionId
        )

        // Update the memory
        try await databaseService.updateMemory(id: memoryId, content: "User prefers strong coffee in the morning")

        // Verify update
        let memories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].content, "User prefers strong coffee in the morning")
    }

    func testDeleteMemory() async throws {
        let sessionId = UUID()

        // Insert two memories
        let memoryId1 = try await databaseService.insertMemory(
            content: "Memory to keep",
            type: .fact,
            confidence: 0.8,
            sourceSessionId: sessionId
        )

        let memoryId2 = try await databaseService.insertMemory(
            content: "Memory to delete",
            type: .fact,
            confidence: 0.6,
            sourceSessionId: sessionId
        )

        // Delete one memory
        try await databaseService.deleteMemory(id: memoryId2)

        // Verify only one remains
        let memories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].id, memoryId1)
        XCTAssertEqual(memories[0].content, "Memory to keep")
    }

    func testTouchMemories() async throws {
        let sessionId = UUID()

        // Insert memory
        let memoryId = try await databaseService.insertMemory(
            content: "Test memory",
            type: .context,
            confidence: 0.75,
            sourceSessionId: sessionId
        )

        // Touch the memory to update last_accessed
        try await databaseService.touchMemories(ids: [memoryId])

        // Verify memory still exists (last_accessed is internal)
        let memories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(memories.count, 1)
    }

    func testGetAllMemoriesLimit() async throws {
        let sessionId = UUID()

        // Insert 5 memories
        for i in 1...5 {
            _ = try await databaseService.insertMemory(
                content: "Memory \(i)",
                type: .fact,
                confidence: Double(i) * 0.1,
                sourceSessionId: sessionId
            )
        }

        // Request only 3
        let memories = try await databaseService.getAllMemories(limit: 3)

        XCTAssertEqual(memories.count, 3, "Should return only 3 memories")
    }

    // MARK: - Memory Types Tests

    func testAllMemoryTypes() async throws {
        let sessionId = UUID()

        // Insert one of each type
        _ = try await databaseService.insertMemory(
            content: "Prefers bullet points",
            type: .preference,
            confidence: 0.9,
            sourceSessionId: sessionId
        )

        _ = try await databaseService.insertMemory(
            content: "Works at Anthropic",
            type: .fact,
            confidence: 0.95,
            sourceSessionId: sessionId
        )

        _ = try await databaseService.insertMemory(
            content: "Usually asks about code in mornings",
            type: .pattern,
            confidence: 0.7,
            sourceSessionId: sessionId
        )

        _ = try await databaseService.insertMemory(
            content: "Currently debugging SeleneChat",
            type: .context,
            confidence: 0.8,
            sourceSessionId: sessionId
        )

        let memories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(memories.count, 4, "Should have 4 memories of different types")

        let types = Set(memories.map { $0.memoryType })
        XCTAssertTrue(types.contains(.preference))
        XCTAssertTrue(types.contains(.fact))
        XCTAssertTrue(types.contains(.pattern))
        XCTAssertTrue(types.contains(.context))
    }

    // MARK: - ConversationMemory Model Tests

    func testConversationMemoryModel() {
        let memory = ConversationMemory(
            id: 1,
            content: "Test content",
            sourceSessionId: UUID().uuidString,
            memoryType: .preference,
            confidence: 0.85,
            lastAccessed: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(memory.id, 1)
        XCTAssertEqual(memory.content, "Test content")
        XCTAssertEqual(memory.memoryType, ConversationMemory.MemoryType.preference)
        XCTAssertEqual(memory.confidence, 0.85, accuracy: 0.01)
    }

    func testMemoryTypeRawValues() {
        XCTAssertEqual(ConversationMemory.MemoryType.preference.rawValue, "preference")
        XCTAssertEqual(ConversationMemory.MemoryType.fact.rawValue, "fact")
        XCTAssertEqual(ConversationMemory.MemoryType.pattern.rawValue, "pattern")
        XCTAssertEqual(ConversationMemory.MemoryType.context.rawValue, "context")
    }

    // MARK: - Integration Tests

    func testFullConversationMemoryFlow() async throws {
        let sessionId = UUID()

        // 1. Save a conversation exchange
        try await databaseService.saveConversationMessage(
            sessionId: sessionId,
            role: "user",
            content: "I'm working on the Selene project for ADHD note management"
        )

        try await databaseService.saveConversationMessage(
            sessionId: sessionId,
            role: "assistant",
            content: "I understand you're working on Selene, an ADHD-focused knowledge management system."
        )

        // 2. Extract and store a memory (simulating what MemoryService would do)
        let memoryId = try await databaseService.insertMemory(
            content: "User is working on Selene, an ADHD-focused knowledge management project",
            type: .fact,
            confidence: 0.9,
            sourceSessionId: sessionId
        )

        // 3. Verify conversation was stored
        let messages = try await databaseService.getRecentMessages(sessionId: sessionId, limit: 10)
        XCTAssertEqual(messages.count, 2)

        // 4. Verify memory was stored
        let memories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].id, memoryId)

        // 5. Update memory (simulating consolidation UPDATE)
        try await databaseService.updateMemory(
            id: memoryId,
            content: "User is actively developing Selene, an ADHD-focused knowledge management system using Swift and TypeScript"
        )

        // 6. Verify update
        let updatedMemories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertTrue(updatedMemories[0].content.contains("Swift and TypeScript"))

        // 7. Touch memory (simulating retrieval access)
        try await databaseService.touchMemories(ids: [memoryId])

        // Flow complete - all operations successful
        XCTAssertTrue(true, "Full conversation memory flow completed successfully")
    }

    func testMultipleSessionsWithMemories() async throws {
        let session1 = UUID()
        let session2 = UUID()

        // Session 1: Talk about coffee
        try await databaseService.saveConversationMessage(sessionId: session1, role: "user", content: "I need coffee")
        _ = try await databaseService.insertMemory(
            content: "User drinks coffee",
            type: .preference,
            confidence: 0.8,
            sourceSessionId: session1
        )

        // Session 2: Talk about coding
        try await databaseService.saveConversationMessage(sessionId: session2, role: "user", content: "Help with Swift")
        _ = try await databaseService.insertMemory(
            content: "User codes in Swift",
            type: .fact,
            confidence: 0.9,
            sourceSessionId: session2
        )

        // Verify memories from different sessions
        let allMemories = try await databaseService.getAllMemories(limit: 10)
        XCTAssertEqual(allMemories.count, 2)

        // Both sessions contributed memories
        let sessionIds = Set(allMemories.compactMap { $0.sourceSessionId })
        XCTAssertEqual(sessionIds.count, 2)
    }

    // MARK: - Embedding Methods Tests

    func testGetAllMemoriesWithEmbeddings() async throws {
        let sessionId = UUID()
        let embedding1: [Float] = [0.1, 0.2, 0.3]
        let embedding2: [Float] = [0.4, 0.5, 0.6]

        // Insert memories - one with embedding, one without
        _ = try await databaseService.insertMemory(
            content: "User prefers dark mode",
            type: .preference,
            confidence: 0.9,
            sourceSessionId: sessionId,
            embedding: embedding1
        )
        _ = try await databaseService.insertMemory(
            content: "User works on Selene",
            type: .fact,
            confidence: 0.8,
            sourceSessionId: sessionId
        )
        _ = try await databaseService.insertMemory(
            content: "User likes Swift",
            type: .preference,
            confidence: 0.7,
            sourceSessionId: sessionId,
            embedding: embedding2
        )

        let results = try await databaseService.getAllMemoriesWithEmbeddings()

        XCTAssertEqual(results.count, 3)

        let withEmbeddings = results.filter { $0.embedding != nil }
        let withoutEmbeddings = results.filter { $0.embedding == nil }
        XCTAssertEqual(withEmbeddings.count, 2)
        XCTAssertEqual(withoutEmbeddings.count, 1)

        // Verify embedding values round-trip
        if let firstEmb = results.first(where: { $0.memory.content == "User prefers dark mode" })?.embedding {
            XCTAssertEqual(firstEmb.count, 3)
            XCTAssertEqual(firstEmb[0], 0.1, accuracy: 0.0001)
        } else {
            XCTFail("Expected embedding for first memory")
        }
    }

    func testSaveMemoryEmbedding() async throws {
        let sessionId = UUID()

        let memoryId = try await databaseService.insertMemory(
            content: "User likes TypeScript",
            type: .preference,
            confidence: 0.8,
            sourceSessionId: sessionId
        )

        // Verify no embedding initially
        let before = try await databaseService.getAllMemoriesWithEmbeddings()
        XCTAssertNil(before.first?.embedding)

        // Save embedding
        let embedding: [Float] = [0.1, 0.2, 0.3, 0.4]
        try await databaseService.saveMemoryEmbedding(id: memoryId, embedding: embedding)

        // Verify embedding was saved
        let after = try await databaseService.getAllMemoriesWithEmbeddings()
        XCTAssertNotNil(after.first?.embedding)
        XCTAssertEqual(after.first?.embedding?.count, 4)
        XCTAssertEqual(after.first?.embedding?[0] ?? 0, 0.1, accuracy: 0.0001)
    }

    func testUpdateMemoryWithEmbedding() async throws {
        let sessionId = UUID()
        let originalEmbedding: [Float] = [0.1, 0.2, 0.3]

        let memoryId = try await databaseService.insertMemory(
            content: "User likes coffee",
            type: .preference,
            confidence: 0.8,
            sourceSessionId: sessionId,
            embedding: originalEmbedding
        )

        let newEmbedding: [Float] = [0.4, 0.5, 0.6]
        try await databaseService.updateMemory(
            id: memoryId,
            content: "User loves strong coffee",
            embedding: newEmbedding
        )

        let results = try await databaseService.getAllMemoriesWithEmbeddings()
        XCTAssertEqual(results.first?.memory.content, "User loves strong coffee")
        XCTAssertEqual(results.first?.embedding?[0] ?? 0, 0.4, accuracy: 0.0001)
    }
}
