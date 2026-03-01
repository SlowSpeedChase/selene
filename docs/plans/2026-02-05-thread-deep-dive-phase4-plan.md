# Thread Deep-Dive (Phase 4) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable dialogue-based exploration of threads where Selene identifies tensions, asks clarifying questions, and proposes concrete actions.

**Architecture:** QueryAnalyzer detects deep-dive intent. DeepDivePromptBuilder creates specialized prompts using ThinkingPartnerContextBuilder. ActionExtractor parses LLM responses for proposed actions. ActionService captures actions and optionally sends to Things 3.

**Tech Stack:** Swift 5.9, SwiftUI, Ollama (mistral:7b), ThinkingPartnerContextBuilder, existing ThingsURLService

---

## Task 1: Add Deep-Dive Intent Detection to QueryAnalyzer

**Files:**
- Modify: `SeleneChat/Sources/Services/QueryAnalyzer.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/QueryAnalyzerDeepDiveTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class QueryAnalyzerDeepDiveTests: XCTestCase {

    let analyzer = QueryAnalyzer()

    func testDetectsDeepDiveIntent() {
        // "Let's dig into X" patterns
        let intent1 = analyzer.detectDeepDiveIntent("let's dig into Event Architecture")
        XCTAssertEqual(intent1?.threadName, "Event Architecture")

        let intent2 = analyzer.detectDeepDiveIntent("dig into project planning")
        XCTAssertEqual(intent2?.threadName, "project planning")

        // "Explore X thread" patterns
        let intent3 = analyzer.detectDeepDiveIntent("explore the ADHD strategies thread")
        XCTAssertEqual(intent3?.threadName, "ADHD strategies")

        // "Help me think through X"
        let intent4 = analyzer.detectDeepDiveIntent("help me think through Event Architecture")
        XCTAssertEqual(intent4?.threadName, "Event Architecture")
    }

    func testNonDeepDiveQueriesReturnNil() {
        XCTAssertNil(analyzer.detectDeepDiveIntent("what's emerging"))
        XCTAssertNil(analyzer.detectDeepDiveIntent("show me my notes"))
        XCTAssertNil(analyzer.detectDeepDiveIntent("how am I doing"))
    }

    func testDeepDiveQueryTypeDetected() {
        let result = analyzer.analyze("let's dig into Event Architecture")
        XCTAssertEqual(result.queryType, .deepDive)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter QueryAnalyzerDeepDiveTests`
Expected: FAIL with "has no member 'detectDeepDiveIntent'" or "has no member 'deepDive'"

**Step 3: Add implementation to QueryAnalyzer.swift**

Add to QueryType enum:
```swift
case deepDive     // Thread deep-dive: "dig into X", "explore X thread"
```

Add new struct:
```swift
struct DeepDiveIntent {
    let threadName: String
}
```

Add detection patterns:
```swift
private let deepDiveIndicators = [
    "dig into", "let's dig into", "lets dig into",
    "explore", "help me think through", "think through",
    "unpack", "dive into", "deep dive"
]
```

Add method:
```swift
func detectDeepDiveIntent(_ query: String) -> DeepDiveIntent? {
    let lowercased = query.lowercased()

    for indicator in deepDiveIndicators {
        if lowercased.contains(indicator) {
            // Extract thread name after indicator
            if let name = extractDeepDiveThreadName(from: lowercased, indicator: indicator) {
                return DeepDiveIntent(threadName: name)
            }
        }
    }

    return nil
}

private func extractDeepDiveThreadName(from query: String, indicator: String) -> String? {
    guard let range = query.range(of: indicator) else { return nil }
    var name = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)

    // Remove trailing "thread" if present
    if name.hasSuffix(" thread") {
        name = String(name.dropLast(7)).trimmingCharacters(in: .whitespaces)
    }

    // Remove leading "the" if present
    if name.hasPrefix("the ") {
        name = String(name.dropFirst(4))
    }

    return name.isEmpty ? nil : name
}
```

Update detectQueryType to check for deep-dive:
```swift
// Check deep-dive before thread queries
if detectDeepDiveIntent(query) != nil {
    return .deepDive
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter QueryAnalyzerDeepDiveTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/QueryAnalyzer.swift SeleneChat/Tests/SeleneChatTests/Services/QueryAnalyzerDeepDiveTests.swift
git commit -m "feat(deep-dive): add deep-dive intent detection to QueryAnalyzer"
```

---

## Task 2: Create DeepDivePromptBuilder

**Files:**
- Create: `SeleneChat/Sources/Services/DeepDivePromptBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/DeepDivePromptBuilderTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class DeepDivePromptBuilderTests: XCTestCase {

    func testBuildInitialPromptIncludesThreadContext() {
        let builder = DeepDivePromptBuilder()

        let thread = Thread.mock(
            name: "Event Architecture",
            summary: "Exploring event-driven patterns",
            why: "Need better decoupling"
        )
        let notes = [
            Note.mock(title: "Testing strategies", content: "Unit vs integration debate"),
            Note.mock(title: "Event sourcing", content: "CQRS considerations")
        ]

        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes)

        XCTAssertTrue(prompt.contains("Event Architecture"))
        XCTAssertTrue(prompt.contains("tensions"))
        XCTAssertTrue(prompt.contains("Testing strategies"))
        XCTAssertTrue(prompt.contains("thinking partner"))
    }

    func testBuildFollowUpPromptIncludesConversationHistory() {
        let builder = DeepDivePromptBuilder()

        let thread = Thread.mock(name: "Event Architecture")
        let notes = [Note.mock(title: "Note 1")]
        let history = "User: What tensions do you see?\nSelene: I see a debate about testing."
        let currentQuery = "Tell me more about the testing debate"

        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: notes,
            conversationHistory: history,
            currentQuery: currentQuery
        )

        XCTAssertTrue(prompt.contains("Event Architecture"))
        XCTAssertTrue(prompt.contains("testing debate"))
        XCTAssertTrue(prompt.contains(history))
    }

    func testPromptIncludesActionGuidance() {
        let builder = DeepDivePromptBuilder()

        let thread = Thread.mock(name: "Test Thread")
        let prompt = builder.buildInitialPrompt(thread: thread, notes: [])

        XCTAssertTrue(prompt.contains("concrete") || prompt.contains("action"))
        XCTAssertTrue(prompt.contains("[ACTION:"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter DeepDivePromptBuilderTests`
Expected: FAIL with "Cannot find 'DeepDivePromptBuilder'"

**Step 3: Write implementation**

```swift
import Foundation

/// Builds specialized prompts for thread deep-dive exploration
class DeepDivePromptBuilder {
    private let contextBuilder = ThinkingPartnerContextBuilder()

    /// Build the initial prompt when starting a deep-dive
    func buildInitialPrompt(thread: Thread, notes: [Note]) -> String {
        let context = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)

        return """
        You are Selene, a thinking partner for someone with ADHD.
        The user wants to explore a specific thread of thinking.
        Help them understand what they've been thinking, where the tensions are, and what actions might emerge.

        \(context)

        Task:
        1. Synthesize the key ideas in this thread (2-3 sentences)
        2. Identify tensions, contradictions, or unresolved questions you see
        3. Ask 1-2 clarifying questions to help them think deeper

        This is a dialogue. Don't dump everything at once. Start with synthesis and tensions, then engage.

        When you identify a concrete next action the user agrees to, format it as:
        [ACTION: Brief action description | ENERGY: high/medium/low | TIMEFRAME: today/this-week/someday]

        Keep your response under 200 words.
        """
    }

    /// Build follow-up prompt with conversation history
    func buildFollowUpPrompt(
        thread: Thread,
        notes: [Note],
        conversationHistory: String,
        currentQuery: String
    ) -> String {
        let context = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)

        return """
        You are Selene, a thinking partner for someone with ADHD.
        You're in a dialogue about the "\(thread.name)" thread.

        \(context)

        ## Conversation so far:
        \(conversationHistory)

        ## User's latest message:
        \(currentQuery)

        Task:
        - Respond to what they said
        - Build toward concrete action if appropriate
        - Keep asking questions until they're ready for action

        When you identify a concrete next action the user agrees to, format it as:
        [ACTION: Brief action description | ENERGY: high/medium/low | TIMEFRAME: today/this-week/someday]

        Keep your response under 150 words.
        """
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter DeepDivePromptBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/DeepDivePromptBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/DeepDivePromptBuilderTests.swift
git commit -m "feat(deep-dive): add DeepDivePromptBuilder for thread exploration prompts"
```

---

## Task 3: Create ActionExtractor

**Files:**
- Create: `SeleneChat/Sources/Services/ActionExtractor.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ActionExtractorTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class ActionExtractorTests: XCTestCase {

    let extractor = ActionExtractor()

    func testExtractsActionFromResponse() {
        let response = """
        Based on our discussion, it sounds like you want to commit to a testing approach.

        [ACTION: Set up contract tests for 2 event types | ENERGY: medium | TIMEFRAME: this-week]

        Does that feel like the right next step?
        """

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].description, "Set up contract tests for 2 event types")
        XCTAssertEqual(actions[0].energy, .medium)
        XCTAssertEqual(actions[0].timeframe, .thisWeek)
    }

    func testExtractsMultipleActions() {
        let response = """
        Two things emerged:
        [ACTION: Write testing decision doc | ENERGY: low | TIMEFRAME: today]
        [ACTION: Spike contract testing framework | ENERGY: high | TIMEFRAME: this-week]
        """

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].description, "Write testing decision doc")
        XCTAssertEqual(actions[1].description, "Spike contract testing framework")
    }

    func testNoActionsReturnsEmptyArray() {
        let response = "Let's think about this more. What aspects concern you most?"

        let actions = extractor.extractActions(from: response)

        XCTAssertTrue(actions.isEmpty)
    }

    func testRemovesActionMarkersFromDisplay() {
        let response = """
        Great idea!
        [ACTION: Do the thing | ENERGY: high | TIMEFRAME: today]
        Let me know when done.
        """

        let cleaned = extractor.removeActionMarkers(from: response)

        XCTAssertFalse(cleaned.contains("[ACTION:"))
        XCTAssertTrue(cleaned.contains("Great idea!"))
        XCTAssertTrue(cleaned.contains("Let me know when done."))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ActionExtractorTests`
Expected: FAIL

**Step 3: Write implementation**

```swift
import Foundation

/// Extracts action items from LLM responses
class ActionExtractor {

    struct ExtractedAction: Equatable {
        let description: String
        let energy: EnergyLevel
        let timeframe: Timeframe

        enum EnergyLevel: String {
            case high, medium, low
        }

        enum Timeframe: String {
            case today = "today"
            case thisWeek = "this-week"
            case someday = "someday"
        }
    }

    /// Extract all actions from an LLM response
    func extractActions(from response: String) -> [ExtractedAction] {
        var actions: [ExtractedAction] = []

        // Pattern: [ACTION: description | ENERGY: level | TIMEFRAME: time]
        let pattern = #"\[ACTION:\s*(.+?)\s*\|\s*ENERGY:\s*(\w+)\s*\|\s*TIMEFRAME:\s*([\w-]+)\s*\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return actions
        }

        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: range)

        for match in matches {
            guard match.numberOfRanges == 4,
                  let descRange = Range(match.range(at: 1), in: response),
                  let energyRange = Range(match.range(at: 2), in: response),
                  let timeRange = Range(match.range(at: 3), in: response) else {
                continue
            }

            let description = String(response[descRange]).trimmingCharacters(in: .whitespaces)
            let energyStr = String(response[energyRange]).lowercased()
            let timeStr = String(response[timeRange]).lowercased()

            let energy = ExtractedAction.EnergyLevel(rawValue: energyStr) ?? .medium
            let timeframe = ExtractedAction.Timeframe(rawValue: timeStr) ?? .someday

            actions.append(ExtractedAction(
                description: description,
                energy: energy,
                timeframe: timeframe
            ))
        }

        return actions
    }

    /// Remove action markers from response for display
    func removeActionMarkers(from response: String) -> String {
        let pattern = #"\[ACTION:\s*.+?\s*\|\s*ENERGY:\s*\w+\s*\|\s*TIMEFRAME:\s*[\w-]+\s*\]\n?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return response
        }

        let range = NSRange(response.startIndex..., in: response)
        return regex.stringByReplacingMatches(in: response, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ActionExtractorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/ActionExtractor.swift SeleneChat/Tests/SeleneChatTests/Services/ActionExtractorTests.swift
git commit -m "feat(deep-dive): add ActionExtractor for parsing actions from LLM responses"
```

---

## Task 4: Create ActionService

**Files:**
- Create: `SeleneChat/Sources/Services/ActionService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ActionServiceTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class ActionServiceTests: XCTestCase {

    func testCaptureActionStoresInMemory() async {
        let service = ActionService()

        let action = ActionExtractor.ExtractedAction(
            description: "Set up contract tests",
            energy: .medium,
            timeframe: .thisWeek
        )

        await service.capture(action, threadName: "Event Architecture")

        let captured = await service.getCapturedActions()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].action.description, "Set up contract tests")
        XCTAssertEqual(captured[0].threadName, "Event Architecture")
    }

    func testClearActionsClearsMemory() async {
        let service = ActionService()

        let action = ActionExtractor.ExtractedAction(
            description: "Test action",
            energy: .low,
            timeframe: .today
        )

        await service.capture(action, threadName: "Test Thread")
        await service.clearActions()

        let captured = await service.getCapturedActions()
        XCTAssertTrue(captured.isEmpty)
    }

    func testBuildThingsTaskFromAction() {
        let service = ActionService()

        let action = ActionExtractor.ExtractedAction(
            description: "Write testing doc",
            energy: .high,
            timeframe: .today
        )

        let task = service.buildThingsTask(from: action, threadName: "Event Architecture")

        XCTAssertEqual(task.title, "Write testing doc")
        XCTAssertTrue(task.notes?.contains("Event Architecture") ?? false)
        XCTAssertTrue(task.tags.contains("selene"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ActionServiceTests`
Expected: FAIL

**Step 3: Write implementation**

```swift
import Foundation

/// Captures and manages actions extracted from deep-dive conversations
actor ActionService {

    struct CapturedAction {
        let action: ActionExtractor.ExtractedAction
        let threadName: String
        let capturedAt: Date
    }

    private var capturedActions: [CapturedAction] = []
    private let thingsService = ThingsURLService()

    /// Capture an action from a deep-dive conversation
    func capture(_ action: ActionExtractor.ExtractedAction, threadName: String) {
        let captured = CapturedAction(
            action: action,
            threadName: threadName,
            capturedAt: Date()
        )
        capturedActions.append(captured)
    }

    /// Get all captured actions
    func getCapturedActions() -> [CapturedAction] {
        return capturedActions
    }

    /// Clear all captured actions
    func clearActions() {
        capturedActions.removeAll()
    }

    /// Build a Things task from an extracted action
    nonisolated func buildThingsTask(
        from action: ActionExtractor.ExtractedAction,
        threadName: String
    ) -> ThingsTask {
        let deadline: Date?
        switch action.timeframe {
        case .today:
            deadline = Date()
        case .thisWeek:
            deadline = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        case .someday:
            deadline = nil
        }

        return ThingsTask(
            title: action.description,
            notes: "From Selene thread: \(threadName)\nEnergy: \(action.energy.rawValue)",
            deadline: deadline,
            tags: ["selene", "deep-dive"],
            listName: nil
        )
    }

    /// Send an action to Things 3
    func sendToThings(_ action: ActionExtractor.ExtractedAction, threadName: String) async {
        let task = buildThingsTask(from: action, threadName: threadName)
        await thingsService.addTask(task)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ActionServiceTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/ActionService.swift SeleneChat/Tests/SeleneChatTests/Services/ActionServiceTests.swift
git commit -m "feat(deep-dive): add ActionService for capturing and managing actions"
```

---

## Task 5: Integrate Deep-Dive into ChatViewModel

**Files:**
- Modify: `SeleneChat/Sources/Services/ChatViewModel.swift`
- Test: Integration test via existing test patterns

**Step 1: Add deep-dive handling to ChatViewModel**

Add properties:
```swift
private let deepDivePromptBuilder = DeepDivePromptBuilder()
private let actionExtractor = ActionExtractor()
private let actionService = ActionService()

/// Currently active deep-dive thread (if in deep-dive mode)
@Published var activeDeepDiveThread: Thread?
```

Add method to handle deep-dive queries:
```swift
private func handleDeepDiveQuery(threadName: String, query: String) async throws -> (response: String, citedNotes: [Note], contextNotes: [Note], queryType: String) {
    // Find the thread
    guard let (thread, notes) = try await databaseService.getThreadByName(threadName) else {
        let notFound = "I couldn't find a thread matching \"\(threadName)\". Try \"what's emerging\" to see your active threads."
        return (notFound, [], [], "deep-dive-not-found")
    }

    // Set active thread
    activeDeepDiveThread = thread

    // Build prompt based on whether this is initial or follow-up
    let prompt: String
    if useConversationHistory {
        let priorMessages = Array(currentSession.messages.dropLast())
        let sessionContext = SessionContext(messages: priorMessages)

        if priorMessages.isEmpty {
            prompt = deepDivePromptBuilder.buildInitialPrompt(thread: thread, notes: notes)
        } else {
            prompt = deepDivePromptBuilder.buildFollowUpPrompt(
                thread: thread,
                notes: notes,
                conversationHistory: sessionContext.historyWithSummary(),
                currentQuery: query
            )
        }
    } else {
        prompt = deepDivePromptBuilder.buildInitialPrompt(thread: thread, notes: notes)
    }

    // Generate response
    let response = try await ollamaService.generate(prompt: prompt, model: "mistral:7b")

    // Extract any actions
    let actions = actionExtractor.extractActions(from: response)
    for action in actions {
        await actionService.capture(action, threadName: thread.name)
    }

    // Clean response for display (remove action markers)
    let cleanResponse = actionExtractor.removeActionMarkers(from: response)

    return (cleanResponse, notes, notes, "deep-dive")
}
```

Update sendMessage to check for deep-dive intent:
```swift
// In sendMessage(), after thread query check, add:
if let deepDiveIntent = queryAnalyzer.detectDeepDiveIntent(content) {
    let (response, citedNotes, contextNotes, queryType) = try await handleDeepDiveQuery(
        threadName: deepDiveIntent.threadName,
        query: content
    )
    // ... add message and return (same pattern as thread query)
}
```

**Step 2: Verify build**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/ChatViewModel.swift
git commit -m "feat(deep-dive): integrate deep-dive handling into ChatViewModel"
```

---

## Task 6: Add Deep-Dive Integration Tests

**Files:**
- Create: `SeleneChat/Tests/SeleneChatTests/Integration/DeepDiveIntegrationTests.swift`

**Step 1: Write integration tests**

```swift
import XCTest
@testable import SeleneChat

final class DeepDiveIntegrationTests: XCTestCase {

    // MARK: - Query Detection Flow

    func testDeepDiveQueryDetectionFlow() {
        let analyzer = QueryAnalyzer()

        // User says "let's dig into Event Architecture"
        let query = "let's dig into Event Architecture"
        let result = analyzer.analyze(query)

        XCTAssertEqual(result.queryType, .deepDive)

        let intent = analyzer.detectDeepDiveIntent(query)
        XCTAssertEqual(intent?.threadName, "Event Architecture")
    }

    // MARK: - Prompt Building Flow

    func testDeepDivePromptBuildingFlow() {
        let promptBuilder = DeepDivePromptBuilder()

        let thread = SeleneChat.Thread.mock(
            name: "Event Architecture",
            summary: "Exploring event-driven patterns for better decoupling",
            why: "Current monolith is hard to test"
        )

        let notes = [
            Note.mock(title: "Unit vs Integration", content: "Debating testing approaches"),
            Note.mock(title: "Contract Testing", content: "Could solve interface issues")
        ]

        let prompt = promptBuilder.buildInitialPrompt(thread: thread, notes: notes)

        // Should include thread context
        XCTAssertTrue(prompt.contains("Event Architecture"))
        XCTAssertTrue(prompt.contains("event-driven"))

        // Should include guidance for actions
        XCTAssertTrue(prompt.contains("[ACTION:"))

        // Should include thinking partner framing
        XCTAssertTrue(prompt.contains("thinking partner") || prompt.contains("ADHD"))
    }

    // MARK: - Action Extraction Flow

    func testActionExtractionFromResponse() {
        let extractor = ActionExtractor()

        let mockResponse = """
        Based on your notes, I see tension between wanting comprehensive tests and fast feedback.

        Your note about contract testing seems promising - it could give you interface confidence without slow integration tests.

        [ACTION: Spike contract tests for UserCreated event | ENERGY: medium | TIMEFRAME: this-week]

        Would you like to explore what that spike would look like?
        """

        let actions = extractor.extractActions(from: mockResponse)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].description, "Spike contract tests for UserCreated event")
        XCTAssertEqual(actions[0].energy, .medium)
        XCTAssertEqual(actions[0].timeframe, .thisWeek)

        // Clean response should not have markers
        let cleaned = extractor.removeActionMarkers(from: mockResponse)
        XCTAssertFalse(cleaned.contains("[ACTION:"))
        XCTAssertTrue(cleaned.contains("contract testing seems promising"))
    }

    // MARK: - Full Deep-Dive Flow

    func testEndToEndDeepDiveFlow() async {
        let analyzer = QueryAnalyzer()
        let promptBuilder = DeepDivePromptBuilder()
        let extractor = ActionExtractor()
        let actionService = ActionService()

        // 1. User initiates deep-dive
        let query = "let's dig into Event Architecture"
        let intent = analyzer.detectDeepDiveIntent(query)
        XCTAssertNotNil(intent)

        // 2. Build prompt with thread context
        let thread = SeleneChat.Thread.mock(name: intent!.threadName)
        let notes = [Note.mock(title: "Test Note")]
        let prompt = promptBuilder.buildInitialPrompt(thread: thread, notes: notes)
        XCTAssertTrue(prompt.count > 100)

        // 3. Simulate LLM response with action
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
            description: "Write architecture decision record",
            energy: .low,
            timeframe: .today
        )

        let task = actionService.buildThingsTask(from: action, threadName: "Event Architecture")

        XCTAssertEqual(task.title, "Write architecture decision record")
        XCTAssertTrue(task.notes?.contains("Event Architecture") ?? false)
        XCTAssertTrue(task.tags.contains("selene"))
        XCTAssertTrue(task.tags.contains("deep-dive"))
        XCTAssertNotNil(task.deadline) // today should have deadline
    }
}
```

**Step 2: Run tests**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter DeepDiveIntegrationTests`
Expected: PASS

**Step 3: Commit**

```bash
git add SeleneChat/Tests/SeleneChatTests/Integration/DeepDiveIntegrationTests.swift
git commit -m "test(deep-dive): add integration tests for deep-dive flow"
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `SeleneChat/CLAUDE.md`
- Modify: `docs/plans/2026-02-05-selene-thinking-partner-design.md`

**Step 1: Update SeleneChat/CLAUDE.md**

Add to Key Files:
```markdown
- Sources/Services/DeepDivePromptBuilder.swift - Thread deep-dive prompts
- Sources/Services/ActionExtractor.swift - Parse actions from LLM responses
- Sources/Services/ActionService.swift - Capture and manage actions
```

Add to Test Coverage:
```markdown
- QueryAnalyzerDeepDive - Deep-dive intent detection
- DeepDivePromptBuilder - Prompt construction
- ActionExtractor - Action parsing
- ActionService - Action capture
- DeepDiveIntegration - End-to-end flow
```

**Step 2: Update design doc**

Mark Phase 4 complete:
```markdown
### Phase 4: Thread Deep-Dive ✅ COMPLETE

**Acceptance Criteria:**
- [x] Can have back-and-forth about a thread
- [x] Selene identifies tensions from notes
- [x] Selene proposes concrete actions
- [x] Actions can be captured (even if just displayed)
```

**Step 3: Commit**

```bash
git add SeleneChat/CLAUDE.md docs/plans/2026-02-05-selene-thinking-partner-design.md
git commit -m "docs(deep-dive): update documentation for Phase 4 Thread Deep-Dive"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Deep-dive intent detection | QueryAnalyzer.swift |
| 2 | DeepDivePromptBuilder | Sources/Services/DeepDivePromptBuilder.swift |
| 3 | ActionExtractor | Sources/Services/ActionExtractor.swift |
| 4 | ActionService | Sources/Services/ActionService.swift |
| 5 | ChatViewModel integration | Sources/Services/ChatViewModel.swift |
| 6 | Integration tests | Tests/Integration/DeepDiveIntegrationTests.swift |
| 7 | Documentation | CLAUDE.md, design doc |

**Dependencies:**
- Phase 2 (ThinkingPartnerContextBuilder) provides buildDeepDiveContext()
- Existing ThingsURLService for Things 3 integration
- Thread.mock() and Note.mock() helpers from Phase 3
