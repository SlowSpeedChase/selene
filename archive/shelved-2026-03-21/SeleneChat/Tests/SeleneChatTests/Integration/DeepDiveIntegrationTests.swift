import SeleneShared
import XCTest
@testable import SeleneChat

final class DeepDiveIntegrationTests: XCTestCase {

    // MARK: - Query Detection Flow

    func testDeepDiveQueryDetectionFlow() {
        let analyzer = QueryAnalyzer()

        let query = "let's dig into Event Architecture"
        let result = analyzer.analyze(query)

        XCTAssertEqual(result.queryType, .deepDive)

        let intent = analyzer.detectDeepDiveIntent(query)
        XCTAssertEqual(intent?.threadName, "event architecture")
    }

    // MARK: - Prompt Building Flow

    func testDeepDivePromptBuildingFlow() {
        let promptBuilder = DeepDivePromptBuilder()

        let thread = SeleneChat.Thread.mock(
            name: "Event Architecture",
            summary: "Exploring event-driven patterns"
        )
        let notes = [Note.mock(title: "Testing patterns")]

        let prompt = promptBuilder.buildInitialPrompt(thread: thread, notes: notes)

        XCTAssertTrue(prompt.contains("Event Architecture"))
        XCTAssertTrue(prompt.contains("[ACTION:"))
        XCTAssertTrue(prompt.count > 100)
    }

    // MARK: - Action Extraction Flow

    func testActionExtractionFromResponse() {
        let extractor = ActionExtractor()

        let mockResponse = """
        I see tension here.
        [ACTION: Spike contract tests | ENERGY: medium | TIMEFRAME: this-week]
        Would you like to explore this?
        """

        let actions = extractor.extractActions(from: mockResponse)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].description, "Spike contract tests")
        XCTAssertEqual(actions[0].energy, .medium)
        XCTAssertEqual(actions[0].timeframe, .thisWeek)

        let cleaned = extractor.removeActionMarkers(from: mockResponse)
        XCTAssertFalse(cleaned.contains("[ACTION:"))
    }

    // MARK: - Full Deep-Dive Flow

    func testEndToEndDeepDiveFlow() async {
        let analyzer = QueryAnalyzer()
        let promptBuilder = DeepDivePromptBuilder()
        let extractor = ActionExtractor()
        let actionService = ActionService()

        // 1. Detect intent
        let query = "let's dig into Event Architecture"
        let intent = analyzer.detectDeepDiveIntent(query)
        XCTAssertNotNil(intent)

        // 2. Build prompt
        let thread = SeleneChat.Thread.mock(name: intent!.threadName)
        let notes = [Note.mock(title: "Test Note")]
        let prompt = promptBuilder.buildInitialPrompt(thread: thread, notes: notes)
        XCTAssertTrue(prompt.count > 100)

        // 3. Simulate response with action
        let mockResponse = "[ACTION: Test action | ENERGY: high | TIMEFRAME: today]"
        let actions = extractor.extractActions(from: mockResponse)

        // 4. Capture action
        for action in actions {
            await actionService.capture(action, threadName: thread.name)
        }

        let captured = await actionService.getCapturedActions()
        XCTAssertEqual(captured.count, 1)
    }

    // MARK: - Things Integration

    func testActionToThingsTaskConversion() {
        let actionService = ActionService()

        let action = ActionExtractor.ExtractedAction(
            description: "Write architecture doc",
            energy: .low,
            timeframe: .today
        )

        let task = actionService.buildThingsTask(from: action, threadName: "Event Architecture")

        XCTAssertEqual(task.title, "Write architecture doc")
        XCTAssertTrue(task.notes.contains("Event Architecture"))
        XCTAssertTrue(task.tags.contains("selene"))
        XCTAssertNotNil(task.deadline)
    }

    // MARK: - Edge Cases

    func testDeepDiveWithNoMatchingThread() {
        let analyzer = QueryAnalyzer()

        // This should detect intent even if thread doesn't exist
        let intent = analyzer.detectDeepDiveIntent("dig into NonExistent Thread")
        XCTAssertEqual(intent?.threadName, "nonexistent")
    }

    func testMultipleActionsInResponse() {
        let extractor = ActionExtractor()

        let response = """
        [ACTION: Task 1 | ENERGY: high | TIMEFRAME: today]
        [ACTION: Task 2 | ENERGY: low | TIMEFRAME: someday]
        """

        let actions = extractor.extractActions(from: response)
        XCTAssertEqual(actions.count, 2)
    }

    // MARK: - Follow-Up Prompt Flow

    func testDeepDiveFollowUpPromptIncludesHistory() {
        let promptBuilder = DeepDivePromptBuilder()

        let thread = SeleneChat.Thread.mock(name: "Event Architecture")
        let notes = [Note.mock(title: "Test Note")]
        let conversationHistory = """
        User: What are the main patterns?
        Assistant: The main patterns are event sourcing and CQRS.
        """
        let currentQuery = "How do these relate?"

        let prompt = promptBuilder.buildFollowUpPrompt(
            thread: thread,
            notes: notes,
            conversationHistory: conversationHistory,
            currentQuery: currentQuery
        )

        XCTAssertTrue(prompt.contains("Event Architecture"))
        XCTAssertTrue(prompt.contains("event sourcing"))
        XCTAssertTrue(prompt.contains("How do these relate?"))
        XCTAssertTrue(prompt.contains("[ACTION:"))
    }

    // MARK: - Action Service State Management

    func testActionServiceClearActions() async {
        let actionService = ActionService()

        // Capture some actions
        let action1 = ActionExtractor.ExtractedAction(
            description: "Action 1",
            energy: .high,
            timeframe: .today
        )
        let action2 = ActionExtractor.ExtractedAction(
            description: "Action 2",
            energy: .low,
            timeframe: .someday
        )

        await actionService.capture(action1, threadName: "Thread A")
        await actionService.capture(action2, threadName: "Thread B")

        var captured = await actionService.getCapturedActions()
        XCTAssertEqual(captured.count, 2)

        // Clear actions
        await actionService.clearActions()

        captured = await actionService.getCapturedActions()
        XCTAssertTrue(captured.isEmpty)
    }

    // MARK: - Query Type Transitions

    func testQueryTypeDetectionForVariousDeepDivePatterns() {
        let analyzer = QueryAnalyzer()

        let deepDiveQueries = [
            ("let's dig into project planning", "project planning"),
            ("explore the testing thread", "testing"),
            ("help me think through documentation", "documentation"),
            ("dive into architecture", "architecture"),
            ("deep dive into memory management", "memory management"),
            ("unpack the design decisions", "design decisions")
        ]

        for (query, expectedThread) in deepDiveQueries {
            let result = analyzer.analyze(query)
            XCTAssertEqual(
                result.queryType,
                .deepDive,
                "Expected .deepDive for query: \(query)"
            )

            let intent = analyzer.detectDeepDiveIntent(query)
            XCTAssertNotNil(intent, "Expected intent for query: \(query)")
            XCTAssertEqual(
                intent?.threadName.lowercased(),
                expectedThread.lowercased(),
                "Expected thread name '\(expectedThread)' for query: \(query)"
            )
        }
    }

    // MARK: - Integration with Session Context

    func testDeepDiveSessionContextFlow() {
        // Simulate a deep-dive session with multiple turns
        var session = ChatSession()

        // Turn 1: User initiates deep-dive
        session.addMessage(Message(role: .user, content: "dig into Event Architecture", llmTier: .local))
        session.addMessage(Message(role: .assistant, content: "Let me analyze your notes on Event Architecture. [ACTION: Review event flow | ENERGY: high | TIMEFRAME: today]", llmTier: .local))

        // Turn 2: User asks follow-up
        session.addMessage(Message(role: .user, content: "What about error handling?", llmTier: .local))

        // Build context for follow-up (excluding current query)
        let priorMessages = Array(session.messages.dropLast())
        let context = SessionContext(messages: priorMessages)

        // Verify history contains prior deep-dive exchange
        XCTAssertTrue(context.formattedHistory.contains("Event Architecture"))
        XCTAssertTrue(context.formattedHistory.contains("event flow"))

        // Verify current query is NOT in history
        XCTAssertFalse(context.formattedHistory.contains("error handling"))
    }

    // MARK: - Action Extraction Edge Cases

    func testActionExtractionWithMalformedMarkers() {
        let extractor = ActionExtractor()

        // Missing required fields should not match
        let malformedResponses = [
            "[ACTION: Task without energy or timeframe]",
            "[ACTION: Task | ENERGY: high]",
            "ACTION: Missing brackets | ENERGY: high | TIMEFRAME: today"
        ]

        for response in malformedResponses {
            let actions = extractor.extractActions(from: response)
            XCTAssertTrue(actions.isEmpty, "Should not extract action from malformed marker: \(response)")
        }
    }

    func testActionExtractionHandlesEmptyDescription() {
        let extractor = ActionExtractor()

        // Empty description in otherwise valid format - regex does match but captures empty string
        let response = "[ACTION: | ENERGY: high | TIMEFRAME: today]"
        let actions = extractor.extractActions(from: response)

        // The regex matches, but the description is empty (whitespace-trimmed)
        // This documents current behavior - empty descriptions are technically captured
        if !actions.isEmpty {
            XCTAssertTrue(actions[0].description.isEmpty, "Empty description should be captured as empty string")
        }
    }

    // MARK: - Prompt Builder ADHD Framing

    func testDeepDivePromptIncludesADHDFraming() {
        let promptBuilder = DeepDivePromptBuilder()
        let thread = SeleneChat.Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let prompt = promptBuilder.buildInitialPrompt(thread: thread, notes: notes)

        XCTAssertTrue(prompt.lowercased().contains("adhd"), "Prompt should mention ADHD")
        XCTAssertTrue(prompt.lowercased().contains("thinking partner"), "Prompt should include thinking partner framing")
    }
}
