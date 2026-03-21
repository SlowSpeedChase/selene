import SeleneShared
import XCTest
@testable import SeleneChat

final class ConversationMemoryIntegrationTests: XCTestCase {

    func testSessionContextBuildsFromChatSession() {
        // Create a chat session with messages
        var session = ChatSession()
        session.addMessage(Message(role: .user, content: "What are my active threads?", llmTier: .local))
        session.addMessage(Message(role: .assistant, content: "You have 2 active threads: Project Planning and Health Goals.", llmTier: .local))
        session.addMessage(Message(role: .user, content: "Tell me about the first one", llmTier: .local))

        // Build context from session (excluding last message - the current query)
        let priorMessages = Array(session.messages.dropLast())
        let context = SessionContext(messages: priorMessages)

        // History should include the first exchange
        XCTAssertTrue(context.formattedHistory.contains("active threads"))
        XCTAssertTrue(context.formattedHistory.contains("Project Planning"))

        // Should NOT include the current query
        XCTAssertFalse(context.formattedHistory.contains("first one"))
    }

    func testHistoryTokenEstimation() {
        var session = ChatSession()

        // Add multiple turns
        for i in 0..<10 {
            session.addMessage(Message(role: .user, content: "Question \(i) about topic", llmTier: .local))
            session.addMessage(Message(role: .assistant, content: "Answer \(i) with explanation", llmTier: .local))
        }

        let context = SessionContext(messages: session.messages)

        // Should estimate tokens reasonably
        XCTAssertGreaterThan(context.estimatedTokens, 50)
        XCTAssertLessThan(context.estimatedTokens, 1000)
    }

    func testSummaryKicksInAfterThreshold() {
        var session = ChatSession()

        // Add 12 messages (6 turns) - should trigger summary for first 2 turns
        for i in 0..<6 {
            session.addMessage(Message(role: .user, content: "Topic \(i): detailed question", llmTier: .local))
            session.addMessage(Message(role: .assistant, content: "Response \(i): detailed answer", llmTier: .local))
        }

        let context = SessionContext(messages: session.messages)
        let result = context.historyWithSummary(recentTurnCount: 4)

        // Should have summary section
        XCTAssertTrue(result.contains("[Earlier in conversation:"))

        // Recent 4 turns (8 messages) should be verbatim
        XCTAssertTrue(result.contains("Topic 4"))
        XCTAssertTrue(result.contains("Topic 5"))
        XCTAssertTrue(result.contains("Response 4"))
        XCTAssertTrue(result.contains("Response 5"))
    }

    // MARK: - Prompt Building Tests (Simulates ChatViewModel flow)

    /// Tests the exact flow used in ChatViewModel.handleOllamaQuery()
    func testPromptIncludesConversationHistory() {
        // Simulate: User asks about threads, Selene responds, user asks follow-up
        var session = ChatSession()
        session.addMessage(Message(role: .user, content: "What are my active threads?", llmTier: .local))
        session.addMessage(Message(role: .assistant, content: "You have 2 active threads: Event-Driven Architecture and Project Journey.", llmTier: .local))
        session.addMessage(Message(role: .user, content: "Tell me more about the first one", llmTier: .local))

        // This is exactly what ChatViewModel.handleOllamaQuery() does:
        let priorMessages = Array(session.messages.dropLast())  // Exclude current query
        let sessionContext = SessionContext(messages: priorMessages)

        let historySection: String
        if priorMessages.isEmpty {
            historySection = ""
        } else {
            historySection = """

## Conversation so far:
\(sessionContext.historyWithSummary())

"""
        }

        // Build a mock prompt like ChatViewModel does
        let systemPrompt = "You are Selene, a personal AI assistant."
        let noteContext = "Note 1: Event-Driven Architecture notes..."
        let currentQuery = "Tell me more about the first one"

        let fullPrompt = """
\(systemPrompt)
\(historySection)
Notes:
\(noteContext)

Question: \(currentQuery)
"""

        // Verify: Prompt contains conversation history
        XCTAssertTrue(fullPrompt.contains("## Conversation so far:"))
        XCTAssertTrue(fullPrompt.contains("User: What are my active threads?"))
        XCTAssertTrue(fullPrompt.contains("Selene: You have 2 active threads"))
        XCTAssertTrue(fullPrompt.contains("Event-Driven Architecture"))

        // Verify: Current query is NOT in history section (it's in Question section)
        let historyEndIndex = fullPrompt.range(of: "Notes:")!.lowerBound
        let historyPortion = String(fullPrompt[..<historyEndIndex])
        XCTAssertFalse(historyPortion.contains("Tell me more about the first one"))
    }

    /// Tests that first message has no history (empty session)
    func testFirstMessageHasNoHistory() {
        var session = ChatSession()
        session.addMessage(Message(role: .user, content: "What are my active threads?", llmTier: .local))

        // Simulate ChatViewModel flow
        let priorMessages = Array(session.messages.dropLast())
        let sessionContext = SessionContext(messages: priorMessages)

        let historySection: String
        if priorMessages.isEmpty {
            historySection = ""
        } else {
            historySection = """

## Conversation so far:
\(sessionContext.historyWithSummary())

"""
        }

        // First message should have no history
        XCTAssertTrue(historySection.isEmpty)
        XCTAssertTrue(priorMessages.isEmpty)
    }

    /// Tests multi-turn conversation maintains full context
    func testMultiTurnConversationContext() {
        var session = ChatSession()

        // Turn 1
        session.addMessage(Message(role: .user, content: "Show me notes about ADHD", llmTier: .local))
        session.addMessage(Message(role: .assistant, content: "Here are 3 notes about ADHD: focus strategies, medication notes, and morning routines.", llmTier: .local))

        // Turn 2
        session.addMessage(Message(role: .user, content: "How do those relate to productivity?", llmTier: .local))
        session.addMessage(Message(role: .assistant, content: "The focus strategies note mentions productivity techniques.", llmTier: .local))

        // Turn 3 (current)
        session.addMessage(Message(role: .user, content: "What specific techniques?", llmTier: .local))

        // Build context excluding current query
        let priorMessages = Array(session.messages.dropLast())
        let sessionContext = SessionContext(messages: priorMessages)
        let history = sessionContext.historyWithSummary()

        // Should contain all prior turns
        XCTAssertTrue(history.contains("ADHD"))
        XCTAssertTrue(history.contains("productivity"))
        XCTAssertTrue(history.contains("focus strategies"))

        // Should NOT contain current query
        XCTAssertFalse(history.contains("What specific techniques"))
    }

    /// Tests new session clears memory
    func testNewSessionClearsMemory() {
        // Old session with history
        var oldSession = ChatSession()
        oldSession.addMessage(Message(role: .user, content: "Old conversation topic", llmTier: .local))
        oldSession.addMessage(Message(role: .assistant, content: "Old response", llmTier: .local))

        // New session (simulates Cmd+N or New Chat)
        var newSession = ChatSession()
        newSession.addMessage(Message(role: .user, content: "What did we discuss?", llmTier: .local))

        // Build context from new session
        let priorMessages = Array(newSession.messages.dropLast())
        let sessionContext = SessionContext(messages: priorMessages)

        // New session should have no history
        XCTAssertTrue(priorMessages.isEmpty)
        XCTAssertEqual(sessionContext.formattedHistory, "")
    }
}
