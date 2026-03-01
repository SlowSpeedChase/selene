# Cross-Thread Synthesis (Phase 5) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable users to ask "what should I focus on?" and get prioritization recommendations across all active threads with concrete focus suggestions.

**Architecture:** QueryAnalyzer detects synthesis intent. SynthesisPromptBuilder creates specialized prompts using ThinkingPartnerContextBuilder.buildSynthesisContext(). Response includes recommended thread for transition to deep-dive.

**Tech Stack:** Swift 5.9, SwiftUI, Ollama (mistral:7b), ThinkingPartnerContextBuilder (Phase 2)

---

## Task 1: Add Synthesis Intent Detection to QueryAnalyzer

**Files:**
- Modify: `SeleneChat/Sources/Services/QueryAnalyzer.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/QueryAnalyzerSynthesisTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class QueryAnalyzerSynthesisTests: XCTestCase {

    let analyzer = QueryAnalyzer()

    func testDetectsSynthesisIntent() {
        // "What should I focus on?" patterns
        XCTAssertNotNil(analyzer.detectSynthesisIntent("what should I focus on?"))
        XCTAssertNotNil(analyzer.detectSynthesisIntent("what should i focus on"))
        XCTAssertNotNil(analyzer.detectSynthesisIntent("help me prioritize"))
        XCTAssertNotNil(analyzer.detectSynthesisIntent("what's most important"))
        XCTAssertNotNil(analyzer.detectSynthesisIntent("where should I put my energy"))
        XCTAssertNotNil(analyzer.detectSynthesisIntent("what needs my attention"))
    }

    func testNonSynthesisQueriesReturnNil() {
        XCTAssertNil(analyzer.detectSynthesisIntent("what's emerging"))
        XCTAssertNil(analyzer.detectSynthesisIntent("show me my notes"))
        XCTAssertNil(analyzer.detectSynthesisIntent("dig into Event Architecture"))
    }

    func testSynthesisQueryTypeDetected() {
        let result = analyzer.analyze("what should I focus on?")
        XCTAssertEqual(result.queryType, .synthesis)
    }

    func testSynthesisDetectionIsCaseInsensitive() {
        XCTAssertNotNil(analyzer.detectSynthesisIntent("WHAT SHOULD I FOCUS ON"))
        XCTAssertNotNil(analyzer.detectSynthesisIntent("Help Me Prioritize"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter QueryAnalyzerSynthesisTests`
Expected: FAIL with "has no member 'detectSynthesisIntent'" or "has no member 'synthesis'"

**Step 3: Add implementation to QueryAnalyzer.swift**

Add to QueryType enum:
```swift
case synthesis    // Cross-thread synthesis: "what should I focus on?"
```

Add detection patterns:
```swift
private let synthesisIndicators = [
    "what should i focus on",
    "what should i work on",
    "help me prioritize",
    "what's most important",
    "whats most important",
    "where should i put my energy",
    "what needs my attention",
    "what deserves my focus",
    "prioritize my threads",
    "what's the priority",
    "whats the priority"
]
```

Add method:
```swift
func detectSynthesisIntent(_ query: String) -> Bool {
    let lowercased = query.lowercased()

    for indicator in synthesisIndicators {
        if lowercased.contains(indicator) {
            return true
        }
    }

    return false
}
```

Update detectQueryType to check for synthesis BEFORE deep-dive:
```swift
// Check synthesis before deep-dive
if detectSynthesisIntent(query) {
    return .synthesis
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter QueryAnalyzerSynthesisTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/QueryAnalyzer.swift SeleneChat/Tests/SeleneChatTests/Services/QueryAnalyzerSynthesisTests.swift
git commit -m "feat(synthesis): add synthesis intent detection to QueryAnalyzer"
```

---

## Task 2: Create SynthesisPromptBuilder

**Files:**
- Create: `SeleneChat/Sources/Services/SynthesisPromptBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/SynthesisPromptBuilderTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class SynthesisPromptBuilderTests: XCTestCase {

    func testBuildSynthesisPromptIncludesAllThreads() {
        let builder = SynthesisPromptBuilder()

        let threads = [
            SeleneChat.Thread.mock(name: "Event Architecture", noteCount: 5, momentumScore: 0.8),
            SeleneChat.Thread.mock(name: "Project Planning", noteCount: 3, momentumScore: 0.5),
            SeleneChat.Thread.mock(name: "Health Goals", noteCount: 2, momentumScore: 0.3)
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(title: "Testing patterns")],
            2: [Note.mock(title: "Sprint planning")],
            3: [Note.mock(title: "Exercise routine")]
        ]

        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        XCTAssertTrue(prompt.contains("Event Architecture"))
        XCTAssertTrue(prompt.contains("Project Planning"))
        XCTAssertTrue(prompt.contains("Health Goals"))
        XCTAssertTrue(prompt.contains("prioritize") || prompt.contains("focus"))
    }

    func testSynthesisPromptIncludesMomentumGuidance() {
        let builder = SynthesisPromptBuilder()

        let threads = [SeleneChat.Thread.mock(name: "Test Thread", momentumScore: 0.9)]
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: [:])

        XCTAssertTrue(prompt.contains("momentum"))
    }

    func testSynthesisPromptIncludesRecommendationInstruction() {
        let builder = SynthesisPromptBuilder()

        let threads = [SeleneChat.Thread.mock(name: "Test Thread")]
        let prompt = builder.buildSynthesisPrompt(threads: threads, notesPerThread: [:])

        XCTAssertTrue(prompt.contains("recommend") || prompt.contains("suggest"))
        XCTAssertTrue(prompt.contains("concrete") || prompt.contains("specific"))
    }

    func testSynthesisPromptWithConversationHistory() {
        let builder = SynthesisPromptBuilder()

        let threads = [SeleneChat.Thread.mock(name: "Test Thread")]
        let history = "User: What's happening?\nSelene: You have 3 active threads."

        let prompt = builder.buildSynthesisPromptWithHistory(
            threads: threads,
            notesPerThread: [:],
            conversationHistory: history,
            currentQuery: "what should I focus on?"
        )

        XCTAssertTrue(prompt.contains(history))
        XCTAssertTrue(prompt.contains("what should I focus on"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter SynthesisPromptBuilderTests`
Expected: FAIL

**Step 3: Write implementation**

```swift
import Foundation

/// Builds prompts for cross-thread synthesis and prioritization
class SynthesisPromptBuilder {
    private let contextBuilder = ThinkingPartnerContextBuilder()

    /// Build synthesis prompt for prioritization across threads
    func buildSynthesisPrompt(threads: [Thread], notesPerThread: [Int64: [Note]]) -> String {
        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        return """
        You are Selene, a thinking partner for someone with ADHD.
        The user wants help prioritizing across their threads of thinking.
        Look for momentum, tensions, and connections between threads.

        \(context)

        Task: Help them decide what to focus on by:
        1. Identifying which thread has momentum (recent activity)
        2. Noting any tensions or stuck points you see
        3. Finding connections between threads (if any)
        4. Suggesting 1-2 concrete focus areas
        5. Offering to go deeper on one thread

        Be direct. Avoid "it depends." Make a specific recommendation.

        Format your recommendation as:
        **Recommended Focus:** [Thread Name]
        **Why:** [1-2 sentence reason]

        Keep your response under 200 words.
        """
    }

    /// Build synthesis prompt with conversation history
    func buildSynthesisPromptWithHistory(
        threads: [Thread],
        notesPerThread: [Int64: [Note]],
        conversationHistory: String,
        currentQuery: String
    ) -> String {
        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        return """
        You are Selene, a thinking partner for someone with ADHD.
        The user wants help prioritizing across their threads of thinking.

        \(context)

        ## Conversation so far:
        \(conversationHistory)

        ## User's question:
        \(currentQuery)

        Task: Help them decide what to focus on by:
        1. Identifying which thread has momentum
        2. Noting tensions or stuck points
        3. Finding connections between threads
        4. Suggesting 1-2 concrete focus areas
        5. Offering to go deeper

        Be direct. Make a specific recommendation.

        Format your recommendation as:
        **Recommended Focus:** [Thread Name]
        **Why:** [1-2 sentence reason]

        Keep your response under 200 words.
        """
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter SynthesisPromptBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/SynthesisPromptBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/SynthesisPromptBuilderTests.swift
git commit -m "feat(synthesis): add SynthesisPromptBuilder for cross-thread prioritization"
```

---

## Task 3: Integrate Synthesis into ChatViewModel

**Files:**
- Modify: `SeleneChat/Sources/Services/ChatViewModel.swift`

**Step 1: Add synthesis handling**

Add property:
```swift
private let synthesisPromptBuilder = SynthesisPromptBuilder()
```

Add handleSynthesisQuery method:
```swift
private func handleSynthesisQuery(query: String) async throws -> (response: String, citedNotes: [Note], contextNotes: [Note], queryType: String) {
    // Get all active threads
    let threads = try await databaseService.getActiveThreads(limit: 10)

    guard !threads.isEmpty else {
        let noThreads = "You don't have any active threads yet. Keep capturing notes and threads will emerge as related ideas cluster together."
        return (noThreads, [], [], "synthesis-empty")
    }

    // Get recent notes for each thread
    var notesPerThread: [Int64: [Note]] = [:]
    for thread in threads {
        if let (_, notes) = try await databaseService.getThreadByName(thread.name) {
            notesPerThread[thread.id] = Array(notes.prefix(3))
        }
    }

    // Build prompt
    let prompt: String
    if useConversationHistory {
        let priorMessages = Array(currentSession.messages.dropLast())
        let sessionContext = SessionContext(messages: priorMessages)

        if priorMessages.isEmpty {
            prompt = synthesisPromptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)
        } else {
            prompt = synthesisPromptBuilder.buildSynthesisPromptWithHistory(
                threads: threads,
                notesPerThread: notesPerThread,
                conversationHistory: sessionContext.historyWithSummary(),
                currentQuery: query
            )
        }
    } else {
        prompt = synthesisPromptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)
    }

    // Generate response
    let response = try await ollamaService.generate(prompt: prompt, model: "mistral:7b")

    // Collect all notes for citation
    let allNotes = notesPerThread.values.flatMap { $0 }

    return (response, allNotes, allNotes, "synthesis")
}
```

Update sendMessage to check for synthesis intent (BEFORE deep-dive check):
```swift
// Check for synthesis queries
if queryAnalyzer.detectSynthesisIntent(content) {
    let (response, citedNotes, contextNotes, queryType) = try await handleSynthesisQuery(query: content)
    let assistantMessage = Message(
        role: .assistant,
        content: response,
        llmTier: .local,
        citedNotes: citedNotes,
        contextNotes: contextNotes,
        queryType: queryType
    )
    currentSession.addMessage(assistantMessage)
    await saveSession()
    return
}
```

**Step 2: Verify build**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/ChatViewModel.swift
git commit -m "feat(synthesis): integrate cross-thread synthesis into ChatViewModel"
```

---

## Task 4: Add Synthesis Integration Tests

**Files:**
- Create: `SeleneChat/Tests/SeleneChatTests/Integration/SynthesisIntegrationTests.swift`

**Step 1: Write integration tests**

```swift
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

        // Should include all threads
        XCTAssertTrue(prompt.contains("Thread A"))
        XCTAssertTrue(prompt.contains("Thread B"))
        XCTAssertTrue(prompt.contains("Thread C"))

        // Should include prioritization guidance
        XCTAssertTrue(prompt.contains("momentum") || prompt.contains("focus"))
        XCTAssertTrue(prompt.contains("recommend") || prompt.contains("suggest"))
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

        // Context should prioritize by momentum
        XCTAssertTrue(context.contains("High Momentum"))
        XCTAssertTrue(context.contains("Low Momentum"))
    }

    // MARK: - End-to-End Flow

    func testEndToEndSynthesisFlow() {
        let analyzer = QueryAnalyzer()
        let promptBuilder = SynthesisPromptBuilder()

        // 1. User asks for prioritization
        let query = "what should I focus on?"
        let result = analyzer.analyze(query)
        XCTAssertEqual(result.queryType, .synthesis)

        // 2. Build prompt with threads
        let threads = [
            SeleneChat.Thread.mock(id: 1, name: "Project Alpha", momentumScore: 0.8, summary: "Main project"),
            SeleneChat.Thread.mock(id: 2, name: "Side Quest", momentumScore: 0.3, summary: "Nice to have")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [Note.mock(title: "Alpha progress")],
            2: [Note.mock(title: "Quest idea")]
        ]

        let prompt = promptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)

        // 3. Verify prompt is ready for LLM
        XCTAssertTrue(prompt.count > 200)
        XCTAssertTrue(prompt.contains("Project Alpha"))
        XCTAssertTrue(prompt.contains("**Recommended Focus:**"))
    }

    // MARK: - Conversation History Integration

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

    // MARK: - Edge Cases

    func testSynthesisWithNoThreads() {
        let promptBuilder = SynthesisPromptBuilder()

        let prompt = promptBuilder.buildSynthesisPrompt(threads: [], notesPerThread: [:])

        // Should still produce a valid prompt
        XCTAssertTrue(prompt.count > 100)
    }

    func testSynthesisQueryTypeInAnalyzerDescription() {
        let queryType = QueryAnalyzer.QueryType.synthesis
        XCTAssertEqual(queryType.description, "synthesis")
    }
}
```

**Step 2: Run tests**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter SynthesisIntegrationTests`
Expected: PASS

**Step 3: Commit**

```bash
git add SeleneChat/Tests/SeleneChatTests/Integration/SynthesisIntegrationTests.swift
git commit -m "test(synthesis): add integration tests for cross-thread synthesis"
```

---

## Task 5: Update Documentation

**Files:**
- Modify: `SeleneChat/CLAUDE.md`
- Modify: `docs/plans/2026-02-05-selene-thinking-partner-design.md`

**Step 1: Update SeleneChat/CLAUDE.md**

Add to Key Files:
```markdown
- Sources/Services/SynthesisPromptBuilder.swift - Cross-thread synthesis prompts
```

Add to Test Coverage:
```markdown
- QueryAnalyzerSynthesis - Synthesis intent detection
- SynthesisPromptBuilder - Prompt construction
- SynthesisIntegration - End-to-end flow
```

**Step 2: Update design doc**

Mark Phase 5 complete:
```markdown
### Phase 5: Cross-Thread Synthesis ✅ COMPLETE

Looking across all threads to help prioritize.

**Components:**
- Synthesis prompt - connections, momentum, recommendations
- "What should I focus on?" detection in QueryAnalyzer
- Cross-thread context assembly
- Priority recommendations with reasoning

**Acceptance Criteria:**
- [x] Asking "what should I focus on?" triggers synthesis
- [x] Response considers all active threads
- [x] Makes concrete recommendation (not wishy-washy)
- [x] Can transition to deep-dive on recommended thread
```

**Step 3: Commit**

```bash
git add SeleneChat/CLAUDE.md docs/plans/2026-02-05-selene-thinking-partner-design.md
git commit -m "docs(synthesis): update documentation for Phase 5 Cross-Thread Synthesis"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Synthesis intent detection | QueryAnalyzer.swift |
| 2 | SynthesisPromptBuilder | Sources/Services/SynthesisPromptBuilder.swift |
| 3 | ChatViewModel integration | Sources/Services/ChatViewModel.swift |
| 4 | Integration tests | Tests/Integration/SynthesisIntegrationTests.swift |
| 5 | Documentation | CLAUDE.md, design doc |

**Dependencies:**
- Phase 2 (ThinkingPartnerContextBuilder) provides buildSynthesisContext()
- Thread.mock() and Note.mock() helpers from Phase 3

**Note:** This is the final phase of the Selene Thinking Partner feature. After completion, all 5 phases will be done.
