import SeleneShared
import XCTest
@testable import SeleneChat

final class SynthesisPromptBuilderTests: XCTestCase {

    // MARK: - Build Synthesis Prompt Tests

    func testBuildSynthesisPromptIncludesAllThreads() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Event-Driven Architecture"),
            SeleneChat.Thread.mock(id: 2, name: "Personal Productivity"),
            SeleneChat.Thread.mock(id: 3, name: "Swift Development")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(id: 1, title: "Event sourcing basics")],
            2: [Note.mock(id: 2, title: "Morning routines")],
            3: [Note.mock(id: 3, title: "SwiftUI patterns")]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include all thread names
        XCTAssertTrue(prompt.contains("Event-Driven Architecture"), "Prompt should include first thread name")
        XCTAssertTrue(prompt.contains("Personal Productivity"), "Prompt should include second thread name")
        XCTAssertTrue(prompt.contains("Swift Development"), "Prompt should include third thread name")
    }

    func testSynthesisPromptIncludesMomentumGuidance() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread", momentumScore: 0.8)
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include momentum guidance
        XCTAssertTrue(prompt.lowercased().contains("momentum"), "Prompt should mention momentum")
    }

    func testSynthesisPromptIncludesRecommendationInstruction() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include recommendation instruction
        XCTAssertTrue(prompt.lowercased().contains("recommend"), "Prompt should mention recommend")
        XCTAssertTrue(prompt.lowercased().contains("concrete") || prompt.lowercased().contains("specific"), "Prompt should mention concrete or specific recommendation")
    }

    func testSynthesisPromptIncludesADHDFraming() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include ADHD thinking partner framing
        XCTAssertTrue(prompt.lowercased().contains("adhd"), "Prompt should mention ADHD")
        XCTAssertTrue(prompt.lowercased().contains("thinking partner"), "Prompt should include thinking partner framing")
    }

    func testSynthesisPromptPresentsOptions() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(prompt.contains("2-3"), "Prompt should present multiple options")
        XCTAssertTrue(prompt.lowercased().contains("resonate"), "Prompt should ask what resonates")
    }

    func testSynthesisPromptEncouragesConciseness() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(prompt.contains("Every word earns its place"), "Prompt should encourage conciseness")
    }

    func testSynthesisPromptIncludesDirectnessInstruction() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(prompt.contains("Be direct"), "Prompt should include directness instruction")
        XCTAssertTrue(prompt.lowercased().contains("specific"), "Prompt should encourage specificity")
    }

    // MARK: - Build Synthesis Prompt With History Tests

    func testSynthesisPromptWithConversationHistory() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Architecture Decisions")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(title: "Decision log")]
        ]

        let conversationHistory = """
        User: What should I focus on today?
        Assistant: Based on your threads, I recommend focusing on Architecture Decisions.
        """

        let currentQuery = "Why do you think that's the right choice?"

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPromptWithHistory(
            threads: threads,
            notesPerThread: notesPerThread,
            conversationHistory: conversationHistory,
            currentQuery: currentQuery
        )

        // Should include conversation history
        XCTAssertTrue(prompt.contains("What should I focus on today?"), "Prompt should include user's previous question")
        XCTAssertTrue(prompt.contains("Architecture Decisions"), "Prompt should include thread name from history and context")

        // Should include current query
        XCTAssertTrue(prompt.contains("Why do you think that's the right choice?"), "Prompt should include current query")
    }

    func testSynthesisPromptWithHistoryIncludesThreadContext() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Swift Patterns"),
            SeleneChat.Thread.mock(id: 2, name: "Testing Strategy")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(id: 1, title: "MVVM notes")],
            2: [Note.mock(id: 2, title: "Integration tests")]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPromptWithHistory(
            threads: threads,
            notesPerThread: notesPerThread,
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Follow-up question"
        )

        // Should include thread names from context
        XCTAssertTrue(prompt.contains("Swift Patterns"), "Prompt should include first thread name")
        XCTAssertTrue(prompt.contains("Testing Strategy"), "Prompt should include second thread name")
    }

    func testSynthesisPromptWithHistoryEncouragesConciseness() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPromptWithHistory(
            threads: threads,
            notesPerThread: notesPerThread,
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next question"
        )

        XCTAssertTrue(prompt.contains("Every word earns its place"), "Prompt with history should encourage conciseness")
    }

    func testSynthesisPromptWithHistoryIncludesADHDFraming() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPromptWithHistory(
            threads: threads,
            notesPerThread: notesPerThread,
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next question"
        )

        // Should include ADHD framing
        XCTAssertTrue(prompt.lowercased().contains("adhd"), "Prompt with history should mention ADHD")
        XCTAssertTrue(prompt.lowercased().contains("thinking partner"), "Prompt with history should include thinking partner framing")
    }

    // MARK: - Task Guidance Tests

    func testSynthesisPromptIncludesIdentifyMomentumTask() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include momentum identification task
        XCTAssertTrue(prompt.lowercased().contains("momentum"), "Prompt should include momentum identification")
    }

    func testSynthesisPromptIncludesNoteTensionsTask() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include tensions task
        XCTAssertTrue(prompt.lowercased().contains("tension"), "Prompt should mention identifying tensions")
    }

    func testSynthesisPromptIncludesFindConnectionsTask() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include connections task
        XCTAssertTrue(prompt.lowercased().contains("connection"), "Prompt should mention finding connections")
    }

    func testSynthesisPromptIncludesSuggestFocusTask() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should include focus suggestion task
        XCTAssertTrue(prompt.lowercased().contains("focus"), "Prompt should mention suggesting focus")
    }

    func testSynthesisPromptIncludesOfferDeeperTask() {
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Test Thread")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock()]
        ]

        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // Should offer to go deeper
        XCTAssertTrue(prompt.lowercased().contains("deeper"), "Prompt should offer to go deeper")
    }
}
