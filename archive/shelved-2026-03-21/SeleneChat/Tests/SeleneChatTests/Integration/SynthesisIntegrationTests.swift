import SeleneShared
import XCTest
@testable import SeleneChat

final class SynthesisIntegrationTests: XCTestCase {

    // MARK: - Query Detection Flow

    func testSynthesisQueryDetectionFlow() {
        let analyzer = QueryAnalyzer()

        let queries = [
            "what should I focus on?",
            "help me prioritize",
            "what's most important",
            "where should I put my energy"
        ]

        for query in queries {
            let result = analyzer.analyze(query)
            XCTAssertEqual(result.queryType, .synthesis, "Failed for query: \(query)")
        }
    }

    func testSynthesisVsDeepDiveDistinction() {
        let analyzer = QueryAnalyzer()

        // Synthesis
        XCTAssertEqual(analyzer.analyze("what should I focus on?").queryType, .synthesis)

        // Deep-dive
        XCTAssertEqual(analyzer.analyze("dig into Event Architecture").queryType, .deepDive)

        // Thread list
        XCTAssertEqual(analyzer.analyze("what's emerging").queryType, .thread)
    }

    // MARK: - Prompt Building Flow

    func testSynthesisPromptBuildsWithMultipleThreads() {
        let promptBuilder = SynthesisPromptBuilder()

        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Thread A", momentumScore: 0.9),
            SeleneChat.Thread.mock(id: 2, name: "Thread B", momentumScore: 0.5),
            SeleneChat.Thread.mock(id: 3, name: "Thread C", momentumScore: 0.2)
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(title: "Note A1")],
            2: [Note.mock(title: "Note B1")],
            3: [Note.mock(title: "Note C1")]
        ]

        let prompt = promptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(prompt.contains("Thread A"))
        XCTAssertTrue(prompt.contains("Thread B"))
        XCTAssertTrue(prompt.contains("Thread C"))
        XCTAssertTrue(prompt.contains("momentum") || prompt.contains("focus"))
    }

    // MARK: - Context Builder Integration

    func testSynthesisUsesContextBuilder() {
        let contextBuilder = ThinkingPartnerContextBuilder()

        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "High Momentum", momentumScore: 0.9),
            SeleneChat.Thread.mock(id: 2, name: "Low Momentum", momentumScore: 0.1)
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(title: "Active work")],
            2: [Note.mock(title: "Old idea")]
        ]

        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(context.contains("High Momentum"))
        XCTAssertTrue(context.contains("Low Momentum"))
    }

    // MARK: - End-to-End Flow

    func testEndToEndSynthesisFlow() {
        let analyzer = QueryAnalyzer()
        let promptBuilder = SynthesisPromptBuilder()

        // 1. Detect synthesis intent
        let query = "what should I focus on?"
        let result = analyzer.analyze(query)
        XCTAssertEqual(result.queryType, .synthesis)

        // 2. Build prompt with threads
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Project Alpha", momentumScore: 0.8),
            SeleneChat.Thread.mock(id: 2, name: "Side Quest", momentumScore: 0.3)
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(title: "Alpha progress")],
            2: [Note.mock(title: "Quest idea")]
        ]

        let prompt = promptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // 3. Verify prompt is ready for LLM
        XCTAssertTrue(prompt.count > 200)
        XCTAssertTrue(prompt.contains("Project Alpha"))
        XCTAssertTrue(prompt.contains("2-3"), "Prompt should present options")
    }

    // MARK: - Edge Cases

    func testSynthesisWithEmptyThreads() {
        let promptBuilder = SynthesisPromptBuilder()

        let prompt = promptBuilder.buildSynthesisPrompt(threads: [], notesPerThread: [:])

        // Should still produce valid prompt structure
        XCTAssertTrue(prompt.count > 100)
    }

    func testSynthesisWithConversationHistory() {
        let promptBuilder = SynthesisPromptBuilder()

        let threads = [SeleneChat.Thread.mock(name: "Test Thread")]
        let history = "User: What's happening?\nSelene: You have active threads."

        let prompt = promptBuilder.buildSynthesisPromptWithHistory(
            threads: threads,
            notesPerThread: [:],
            conversationHistory: history,
            currentQuery: "what should I focus on?"
        )

        XCTAssertTrue(prompt.contains(history))
        XCTAssertTrue(prompt.contains("what should I focus on"))
    }

    // MARK: - Momentum Sorting

    func testSynthesisContextSortsByMomentum() {
        let contextBuilder = ThinkingPartnerContextBuilder()

        // Create threads with various momentum scores (intentionally out of order)
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Low Thread", momentumScore: 0.1),
            SeleneChat.Thread.mock(id: 2, name: "High Thread", momentumScore: 0.9),
            SeleneChat.Thread.mock(id: 3, name: "Medium Thread", momentumScore: 0.5)
        ]

        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: [:])

        // High momentum should appear before low momentum in context
        let highIndex = context.range(of: "High Thread")?.lowerBound
        let lowIndex = context.range(of: "Low Thread")?.lowerBound

        XCTAssertNotNil(highIndex)
        XCTAssertNotNil(lowIndex)
        XCTAssertTrue(highIndex! < lowIndex!, "High momentum thread should appear before low momentum thread")
    }

    // MARK: - Note Inclusion

    func testSynthesisContextIncludesNoteTitles() {
        let contextBuilder = ThinkingPartnerContextBuilder()

        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Active Thread", momentumScore: 0.8)
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [
                Note.mock(title: "Important Note"),
                Note.mock(title: "Another Note")
            ]
        ]

        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(context.contains("Important Note"))
        XCTAssertTrue(context.contains("Another Note"))
    }

    // MARK: - Session Integration

    func testSynthesisSessionContextFlow() {
        // Simulate a synthesis session with multiple turns
        var session = ChatSession()

        // Turn 1: User asks for focus recommendation
        session.addMessage(Message(role: .user, content: "what should I focus on?", llmTier: .local))
        session.addMessage(Message(role: .assistant, content: "Based on your threads, I recommend focusing on Project Alpha because it has the highest momentum.", llmTier: .local))

        // Turn 2: User asks follow-up
        session.addMessage(Message(role: .user, content: "Why not Side Quest?", llmTier: .local))

        // Build context for follow-up (excluding current query)
        let priorMessages = Array(session.messages.dropLast())
        let context = SessionContext(messages: priorMessages)

        // Verify history contains prior synthesis exchange
        XCTAssertTrue(context.formattedHistory.contains("focus"))
        XCTAssertTrue(context.formattedHistory.contains("Project Alpha"))

        // Verify current query is NOT in history
        XCTAssertFalse(context.formattedHistory.contains("Side Quest"))
    }

    // MARK: - Query Type Transitions

    func testQueryTypeDetectionForVariousSynthesisPatterns() {
        let analyzer = QueryAnalyzer()

        let synthesisQueries = [
            "what should I focus on",
            "help me prioritize",
            "what's most important",
            "whats most important",
            "where should I put my energy",
            "what needs my attention",
            "what deserves my focus",
            "prioritize my threads",
            "what's the priority",
            "what should I work on"
        ]

        for query in synthesisQueries {
            let result = analyzer.analyze(query)
            XCTAssertEqual(
                result.queryType,
                .synthesis,
                "Expected .synthesis for query: \(query)"
            )
        }
    }

    // MARK: - ADHD Framing

    func testSynthesisPromptIncludesADHDFraming() {
        let promptBuilder = SynthesisPromptBuilder()
        let threads = [SeleneChat.Thread.mock(name: "Test Thread")]

        let prompt = promptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: [:])

        XCTAssertTrue(prompt.lowercased().contains("adhd"), "Prompt should mention ADHD")
        XCTAssertTrue(prompt.lowercased().contains("thinking partner"), "Prompt should include thinking partner framing")
    }

    // MARK: - Recommendation Format

    func testSynthesisPromptIncludesOptionsBasedRecommendation() {
        let promptBuilder = SynthesisPromptBuilder()
        let threads = [SeleneChat.Thread.mock(name: "Test Thread")]

        let prompt = promptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: [:])

        // Should include options-based recommendation format
        XCTAssertTrue(prompt.contains("2-3"), "Prompt should present multiple options")
        XCTAssertTrue(prompt.lowercased().contains("resonate"), "Prompt should ask what resonates")
    }

    // MARK: - Token Budget Handling

    func testSynthesisContextHandlesManyThreads() {
        let contextBuilder = ThinkingPartnerContextBuilder()

        // Create many threads to test token budget handling
        var threads: [SeleneChat.Thread] = []
        for i in 1...20 {
            threads.append(SeleneChat.Thread.mock(
                id: Int64(i),
                name: "Thread \(i)",
                summary: String(repeating: "This is a long summary. ", count: 10),
                momentumScore: Double(i) / 20.0
            ))
        }

        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: [:])

        // Should produce valid context (may truncate some threads)
        XCTAssertTrue(context.count > 100)
        // Highest momentum thread should be included
        XCTAssertTrue(context.contains("Thread 20"))
    }
}
