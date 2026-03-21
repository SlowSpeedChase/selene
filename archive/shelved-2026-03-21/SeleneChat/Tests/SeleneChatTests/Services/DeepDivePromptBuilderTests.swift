import SeleneShared
import XCTest
@testable import SeleneChat

final class DeepDivePromptBuilderTests: XCTestCase {

    // MARK: - Initial Prompt Tests

    func testBuildInitialPromptIncludesThreadContext() {
        let thread = Thread.mock(
            name: "Event-Driven Architecture",
            summary: "Exploring testing strategies"
        )

        let notes = [
            Note.mock(id: 1, title: "Unit tests insufficient", content: "Unit tests don't catch event flow issues."),
            Note.mock(id: 2, title: "Integration tests slow", content: "Integration tests are slow but catch real bugs.")
        ]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        // Should include thread name from context
        XCTAssertTrue(prompt.contains("Event-Driven Architecture"), "Prompt should include thread name")

        // Should include note titles
        XCTAssertTrue(prompt.contains("Unit tests insufficient"), "Prompt should include first note title")
        XCTAssertTrue(prompt.contains("Integration tests slow"), "Prompt should include second note title")

        // Should ask about tensions (part of the thinking partner task)
        XCTAssertTrue(prompt.contains("tension"), "Prompt should mention identifying tensions")
    }

    func testBuildInitialPromptIncludesADHDFraming() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        // Should include ADHD thinking partner framing
        XCTAssertTrue(prompt.lowercased().contains("adhd"), "Prompt should mention ADHD")
        XCTAssertTrue(prompt.lowercased().contains("thinking partner"), "Prompt should include thinking partner framing")
    }

    func testBuildInitialPromptEncouragesConciseness() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        XCTAssertTrue(prompt.contains("Every word earns its place"), "Prompt should encourage conciseness")
    }

    // MARK: - Follow-Up Prompt Tests

    func testBuildFollowUpPromptIncludesConversationHistory() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let conversationHistory = """
        User: What are the main themes?
        Assistant: The main themes appear to be testing and architecture.
        """

        let currentQuery = "How do these relate to microservices?"

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: notes,
            conversationHistory: conversationHistory,
            currentQuery: currentQuery
        )

        // Should include conversation history
        XCTAssertTrue(prompt.contains("What are the main themes?"), "Prompt should include user's previous question")
        XCTAssertTrue(prompt.contains("testing and architecture"), "Prompt should include assistant's previous response")

        // Should include current query
        XCTAssertTrue(prompt.contains("How do these relate to microservices?"), "Prompt should include current query")
    }

    func testBuildFollowUpPromptIncludesThreadContext() {
        let thread = Thread.mock(name: "Architecture Decisions")
        let notes = [Note.mock(title: "Decision log")]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: notes,
            conversationHistory: "User: Question\nAssistant: Answer",
            currentQuery: "Follow-up question"
        )

        // Should include thread context
        XCTAssertTrue(prompt.contains("Architecture Decisions"), "Prompt should include thread name")
    }

    func testBuildFollowUpPromptEncouragesConciseness() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: notes,
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next question"
        )

        XCTAssertTrue(prompt.contains("Every word earns its place"), "Follow-up prompt should encourage conciseness")
    }

    // MARK: - Action Guidance Tests

    func testPromptIncludesActionGuidance() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()

        // Test initial prompt
        let initialPrompt = builder.buildInitialPrompt(thread: thread, notes: notes)
        XCTAssertTrue(initialPrompt.contains("[ACTION:"), "Initial prompt should include action marker format")
        XCTAssertTrue(initialPrompt.contains("ENERGY:"), "Initial prompt should include energy level in action format")
        XCTAssertTrue(initialPrompt.contains("TIMEFRAME:"), "Initial prompt should include timeframe in action format")

        // Test follow-up prompt
        let followUpPrompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: notes,
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next question"
        )
        XCTAssertTrue(followUpPrompt.contains("[ACTION:"), "Follow-up prompt should include action marker format")
    }

    func testActionGuidanceIncludesEnergyLevels() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        // Should include all energy levels
        XCTAssertTrue(prompt.contains("high") || prompt.contains("high/medium/low"), "Prompt should mention energy levels")
    }

    func testActionGuidanceIncludesTimeframes() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        // Should include timeframes
        XCTAssertTrue(
            prompt.contains("today") || prompt.contains("this-week") || prompt.contains("someday"),
            "Prompt should mention timeframes"
        )
    }

    // MARK: - Task Description Tests

    func testInitialPromptIncludesSynthesizeTask() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        // Should include synthesis task
        XCTAssertTrue(prompt.lowercased().contains("synthesize"), "Prompt should include synthesize task")
    }

    func testInitialPromptIncludesClarifyingQuestionsTask() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        // Should ask for clarifying questions
        XCTAssertTrue(prompt.lowercased().contains("clarifying"), "Prompt should mention clarifying questions")
    }
}
