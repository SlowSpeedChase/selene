# Context Builder (Phase 2) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable smart assembly of thread-focused context for briefing, synthesis, and deep-dive queries.

**Architecture:** Extend the existing `ContextBuilder` service with a new `ThinkingPartnerContextBuilder` that builds context from threads (not just notes). Add query type enum for Thinking Partner modes. Integrate with DatabaseService for thread data.

**Tech Stack:** Swift 5.9, SwiftUI, SQLite.swift

---

## Overview

Phase 1 added conversation memory. Phase 2 adds smart context assembly for the three Thinking Partner modes:

1. **Briefing** - "Here's where your thinking is" (threads + momentum + recent notes)
2. **Synthesis** - "What should I focus on?" (cross-thread comparison)
3. **Deep-Dive** - "Let's explore this thread" (full thread history)

The existing `ContextBuilder` handles notes. We'll create `ThinkingPartnerContextBuilder` for thread-focused context.

**Key Design Decisions:**
- Separate service (not extending existing ContextBuilder) for clarity
- Token budget enforcement (max 3000 tokens for context)
- Uses existing DatabaseService methods (`getActiveThreads`, `getThreadByName`)

---

## Task 1: Create ThinkingPartnerQueryType Enum

**Files:**
- Create: `SeleneChat/Sources/Models/ThinkingPartnerQueryType.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Models/ThinkingPartnerQueryTypeTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class ThinkingPartnerQueryTypeTests: XCTestCase {

    func testQueryTypeRawValues() {
        XCTAssertEqual(ThinkingPartnerQueryType.briefing.rawValue, "briefing")
        XCTAssertEqual(ThinkingPartnerQueryType.synthesis.rawValue, "synthesis")
        XCTAssertEqual(ThinkingPartnerQueryType.deepDive.rawValue, "deepDive")
    }

    func testQueryTypeTokenBudgets() {
        // Briefing: concise overview
        XCTAssertEqual(ThinkingPartnerQueryType.briefing.tokenBudget, 1500)
        // Synthesis: moderate for cross-thread
        XCTAssertEqual(ThinkingPartnerQueryType.synthesis.tokenBudget, 2000)
        // Deep-dive: most context needed
        XCTAssertEqual(ThinkingPartnerQueryType.deepDive.tokenBudget, 3000)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerQueryTypeTests`
Expected: FAIL - "ThinkingPartnerQueryType not found"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Query types for Thinking Partner modes
enum ThinkingPartnerQueryType: String {
    case briefing   // Morning briefing - threads + momentum
    case synthesis  // Cross-thread prioritization
    case deepDive   // Single thread exploration

    /// Token budget for context assembly
    var tokenBudget: Int {
        switch self {
        case .briefing: return 1500
        case .synthesis: return 2000
        case .deepDive: return 3000
        }
    }

    /// Description for debugging
    var description: String {
        switch self {
        case .briefing: return "Morning Briefing"
        case .synthesis: return "Cross-Thread Synthesis"
        case .deepDive: return "Thread Deep-Dive"
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerQueryTypeTests`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene
git add SeleneChat/Sources/Models/ThinkingPartnerQueryType.swift SeleneChat/Tests/SeleneChatTests/Models/ThinkingPartnerQueryTypeTests.swift
git commit -m "$(cat <<'EOF'
feat(selenechat): add ThinkingPartnerQueryType enum

Defines briefing, synthesis, and deepDive query types with token budgets.
Part of Thinking Partner Phase 2 - Context Builder.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create ThinkingPartnerContextBuilder Service

**Files:**
- Create: `SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class ThinkingPartnerContextBuilderTests: XCTestCase {

    func testFormatThreadForContext() {
        let thread = Thread(
            id: 1,
            name: "Event-Driven Architecture",
            why: "Exploring testing strategies",
            summary: "Notes about event testing approaches",
            status: "active",
            noteCount: 5,
            momentumScore: 0.8,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        let builder = ThinkingPartnerContextBuilder()
        let formatted = builder.formatThread(thread)

        XCTAssertTrue(formatted.contains("Event-Driven Architecture"))
        XCTAssertTrue(formatted.contains("active"))
        XCTAssertTrue(formatted.contains("5 notes"))
        XCTAssertTrue(formatted.contains("0.8"))
    }

    func testEstimateTokens() {
        let builder = ThinkingPartnerContextBuilder()
        let text = "Hello world this is a test"  // 26 chars
        let tokens = builder.estimateTokens(text)

        XCTAssertEqual(tokens, 6)  // 26 / 4 = 6
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: FAIL - "ThinkingPartnerContextBuilder not found"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Builds context for Thinking Partner queries (briefing, synthesis, deep-dive)
class ThinkingPartnerContextBuilder {

    // MARK: - Thread Formatting

    /// Format a single thread for context
    func formatThread(_ thread: Thread) -> String {
        var result = "**\(thread.name)** (\(thread.status) \(thread.statusEmoji))\n"
        result += "- \(thread.noteCount) notes | Momentum: \(thread.momentumDisplay)\n"
        result += "- Last activity: \(thread.lastActivityDisplay)\n"

        if let why = thread.why, !why.isEmpty {
            result += "- Why: \(why)\n"
        }

        if let summary = thread.summary, !summary.isEmpty {
            let truncatedSummary = String(summary.prefix(150))
            result += "- Summary: \(truncatedSummary)\(summary.count > 150 ? "..." : "")\n"
        }

        return result
    }

    // MARK: - Token Management

    /// Estimate token count (4 chars per token)
    func estimateTokens(_ text: String) -> Int {
        return text.count / 4
    }

    /// Truncate text to fit within token budget
    func truncateToFit(_ text: String, maxTokens: Int) -> String {
        let maxChars = maxTokens * 4
        if text.count <= maxChars {
            return text
        }
        return String(text.prefix(maxChars)) + "\n[Truncated for token limit]"
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene
git add SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat(selenechat): add ThinkingPartnerContextBuilder service

Basic thread formatting and token estimation.
Part of Thinking Partner Phase 2.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add Briefing Context Builder

**Files:**
- Modify: `SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift`
- Modify: `SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift`

**Step 1: Write the failing test**

```swift
// Add to ThinkingPartnerContextBuilderTests.swift

func testBuildBriefingContext() {
    let threads = [
        Thread(
            id: 1,
            name: "Event-Driven Architecture",
            why: "Testing strategies",
            summary: "Exploring event testing",
            status: "active",
            noteCount: 5,
            momentumScore: 0.8,
            lastActivityAt: Date(),
            createdAt: Date()
        ),
        Thread(
            id: 2,
            name: "Project Journey",
            why: nil,
            summary: "Early exploration",
            status: "active",
            noteCount: 3,
            momentumScore: 0.4,
            lastActivityAt: Date().addingTimeInterval(-86400 * 3),
            createdAt: Date()
        )
    ]

    let recentNotes = [
        Note(id: 1, title: "Testing thoughts", content: "Some content about testing", createdAt: Date())
    ]

    let builder = ThinkingPartnerContextBuilder()
    let context = builder.buildBriefingContext(threads: threads, recentNotes: recentNotes)

    // Should include threads
    XCTAssertTrue(context.contains("Event-Driven Architecture"))
    XCTAssertTrue(context.contains("Project Journey"))

    // Should include momentum
    XCTAssertTrue(context.contains("Momentum"))

    // Should include recent notes section
    XCTAssertTrue(context.contains("Recent Notes"))
    XCTAssertTrue(context.contains("Testing thoughts"))
}

func testBriefingContextRespectsTokenBudget() {
    // Create many threads to exceed budget
    var threads: [Thread] = []
    for i in 0..<20 {
        threads.append(Thread(
            id: Int64(i),
            name: "Thread \(i) with a longer name to use more tokens",
            why: "Reason \(i) that is quite detailed",
            summary: "Summary \(i) with substantial content to fill up the token budget",
            status: "active",
            noteCount: i + 1,
            momentumScore: Double(i) / 20.0,
            lastActivityAt: Date(),
            createdAt: Date()
        ))
    }

    let builder = ThinkingPartnerContextBuilder()
    let context = builder.buildBriefingContext(threads: threads, recentNotes: [])

    let tokens = builder.estimateTokens(context)
    XCTAssertLessThanOrEqual(tokens, ThinkingPartnerQueryType.briefing.tokenBudget)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: FAIL - "buildBriefingContext method not found"

**Step 3: Write minimal implementation**

```swift
// Add to ThinkingPartnerContextBuilder.swift

// MARK: - Briefing Context

/// Build context for morning briefing
/// Includes: active threads with momentum, recent notes
func buildBriefingContext(threads: [Thread], recentNotes: [Note]) -> String {
    let tokenBudget = ThinkingPartnerQueryType.briefing.tokenBudget
    var context = "## Active Threads\n\n"
    var currentTokens = estimateTokens(context)

    // Add threads (sorted by momentum, highest first)
    let sortedThreads = threads.sorted { ($0.momentumScore ?? 0) > ($1.momentumScore ?? 0) }

    for thread in sortedThreads {
        let threadText = formatThread(thread) + "\n"
        let threadTokens = estimateTokens(threadText)

        if currentTokens + threadTokens > tokenBudget - 200 {  // Reserve 200 for notes
            break
        }

        context += threadText
        currentTokens += threadTokens
    }

    // Add recent notes section
    if !recentNotes.isEmpty {
        context += "\n## Recent Notes\n\n"

        for note in recentNotes.prefix(5) {
            let noteText = "- \"\(note.title)\" (\(formatDate(note.createdAt)))\n"
            let noteTokens = estimateTokens(noteText)

            if currentTokens + noteTokens > tokenBudget {
                break
            }

            context += noteText
            currentTokens += noteTokens
        }
    }

    return context
}

// MARK: - Helpers

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene
git add SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat(selenechat): add buildBriefingContext for morning briefing

Assembles threads by momentum with recent notes, respecting token budget.
Part of Thinking Partner Phase 2.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add Synthesis Context Builder

**Files:**
- Modify: `SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift`
- Modify: `SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift`

**Step 1: Write the failing test**

```swift
// Add to ThinkingPartnerContextBuilderTests.swift

func testBuildSynthesisContext() {
    let threads = [
        Thread(
            id: 1,
            name: "Event-Driven Architecture",
            why: "Testing strategies",
            summary: "Exploring event testing approaches",
            status: "active",
            noteCount: 5,
            momentumScore: 0.8,
            lastActivityAt: Date(),
            createdAt: Date()
        ),
        Thread(
            id: 2,
            name: "Project Journey",
            why: "Document decisions",
            summary: "Early exploration of documentation",
            status: "active",
            noteCount: 3,
            momentumScore: 0.4,
            lastActivityAt: Date().addingTimeInterval(-86400 * 3),
            createdAt: Date()
        )
    ]

    // Notes per thread
    let notesPerThread: [Int64: [Note]] = [
        1: [
            Note(id: 1, title: "Testing approach", content: "Unit vs integration", createdAt: Date()),
            Note(id: 2, title: "Event schemas", content: "Schema validation", createdAt: Date())
        ],
        2: [
            Note(id: 3, title: "Why document", content: "Future reference", createdAt: Date())
        ]
    ]

    let builder = ThinkingPartnerContextBuilder()
    let context = builder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

    // Should include all threads
    XCTAssertTrue(context.contains("Event-Driven Architecture"))
    XCTAssertTrue(context.contains("Project Journey"))

    // Should include thread summaries
    XCTAssertTrue(context.contains("Testing strategies") || context.contains("event testing"))

    // Should include note titles
    XCTAssertTrue(context.contains("Testing approach"))
    XCTAssertTrue(context.contains("Why document"))

    // Should have cross-thread section header
    XCTAssertTrue(context.contains("Threads for Prioritization"))
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: FAIL - "buildSynthesisContext method not found"

**Step 3: Write minimal implementation**

```swift
// Add to ThinkingPartnerContextBuilder.swift

// MARK: - Synthesis Context

/// Build context for cross-thread synthesis ("what should I focus on?")
/// Includes: all active threads with summaries and recent note titles
func buildSynthesisContext(threads: [Thread], notesPerThread: [Int64: [Note]]) -> String {
    let tokenBudget = ThinkingPartnerQueryType.synthesis.tokenBudget
    var context = "## Threads for Prioritization\n\n"
    var currentTokens = estimateTokens(context)

    // Sort by momentum
    let sortedThreads = threads.sorted { ($0.momentumScore ?? 0) > ($1.momentumScore ?? 0) }

    for thread in sortedThreads {
        var threadSection = formatThread(thread)

        // Add note titles for this thread
        if let notes = notesPerThread[thread.id], !notes.isEmpty {
            threadSection += "  Notes:\n"
            for note in notes.prefix(3) {
                threadSection += "    - \(note.title)\n"
            }
            if notes.count > 3 {
                threadSection += "    - ...and \(notes.count - 3) more\n"
            }
        }

        threadSection += "\n"
        let sectionTokens = estimateTokens(threadSection)

        if currentTokens + sectionTokens > tokenBudget {
            context += "[Additional threads omitted for token limit]\n"
            break
        }

        context += threadSection
        currentTokens += sectionTokens
    }

    return context
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene
git add SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat(selenechat): add buildSynthesisContext for cross-thread prioritization

Assembles all threads with note titles for "what should I focus on?" queries.
Part of Thinking Partner Phase 2.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add Deep-Dive Context Builder

**Files:**
- Modify: `SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift`
- Modify: `SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift`

**Step 1: Write the failing test**

```swift
// Add to ThinkingPartnerContextBuilderTests.swift

func testBuildDeepDiveContext() {
    let thread = Thread(
        id: 1,
        name: "Event-Driven Architecture",
        why: "Exploring testing strategies for event-driven systems",
        summary: "Notes about different testing approaches including unit, integration, and contract testing",
        status: "active",
        noteCount: 3,
        momentumScore: 0.8,
        lastActivityAt: Date(),
        createdAt: Date()
    )

    let notes = [
        Note(id: 1, title: "Unit tests insufficient", content: "Unit tests don't catch event flow issues. Need integration.", createdAt: Date().addingTimeInterval(-86400 * 2)),
        Note(id: 2, title: "Integration tests slow", content: "Integration tests are slow but catch real bugs. Trade-off.", createdAt: Date().addingTimeInterval(-86400)),
        Note(id: 3, title: "Contract testing idea", content: "Maybe contract tests are the middle ground? Test interfaces, not implementations.", createdAt: Date())
    ]

    let builder = ThinkingPartnerContextBuilder()
    let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

    // Should include thread details
    XCTAssertTrue(context.contains("Event-Driven Architecture"))
    XCTAssertTrue(context.contains("Exploring testing strategies"))

    // Should include full note content
    XCTAssertTrue(context.contains("Unit tests don't catch"))
    XCTAssertTrue(context.contains("Integration tests are slow"))
    XCTAssertTrue(context.contains("contract tests are the middle ground"))

    // Should have chronological ordering header
    XCTAssertTrue(context.contains("Thread Notes"))
}

func testDeepDiveContextRespectsTokenBudget() {
    let thread = Thread(
        id: 1,
        name: "Test Thread",
        why: nil,
        summary: nil,
        status: "active",
        noteCount: 50,
        momentumScore: 0.5,
        lastActivityAt: Date(),
        createdAt: Date()
    )

    // Create many notes with substantial content
    var notes: [Note] = []
    for i in 0..<50 {
        notes.append(Note(
            id: i,
            title: "Note \(i)",
            content: String(repeating: "This is substantial content for note \(i). ", count: 20),
            createdAt: Date().addingTimeInterval(Double(-i * 86400))
        ))
    }

    let builder = ThinkingPartnerContextBuilder()
    let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

    let tokens = builder.estimateTokens(context)
    XCTAssertLessThanOrEqual(tokens, ThinkingPartnerQueryType.deepDive.tokenBudget)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: FAIL - "buildDeepDiveContext method not found"

**Step 3: Write minimal implementation**

```swift
// Add to ThinkingPartnerContextBuilder.swift

// MARK: - Deep-Dive Context

/// Build context for thread deep-dive exploration
/// Includes: full thread details + all notes with content (chronological)
func buildDeepDiveContext(thread: Thread, notes: [Note]) -> String {
    let tokenBudget = ThinkingPartnerQueryType.deepDive.tokenBudget
    var context = "## Thread: \(thread.name)\n\n"

    // Thread metadata
    context += "Status: \(thread.status) \(thread.statusEmoji)\n"
    context += "Notes: \(thread.noteCount) | Momentum: \(thread.momentumDisplay)\n"

    if let why = thread.why, !why.isEmpty {
        context += "Why this emerged: \(why)\n"
    }

    if let summary = thread.summary, !summary.isEmpty {
        context += "Summary: \(summary)\n"
    }

    context += "\n## Thread Notes (chronological)\n\n"

    var currentTokens = estimateTokens(context)

    // Sort notes chronologically (oldest first for narrative flow)
    let sortedNotes = notes.sorted { $0.createdAt < $1.createdAt }

    for note in sortedNotes {
        var noteSection = "### \(note.title) (\(formatDate(note.createdAt)))\n"
        noteSection += "\(note.content)\n\n"

        let noteTokens = estimateTokens(noteSection)

        if currentTokens + noteTokens > tokenBudget {
            context += "[Older notes omitted for token limit - \(sortedNotes.count - sortedNotes.firstIndex(where: { $0.id == note.id })!) remaining]\n"
            break
        }

        context += noteSection
        currentTokens += noteTokens
    }

    return context
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene
git add SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat(selenechat): add buildDeepDiveContext for thread exploration

Assembles full thread details with chronological notes for deep-dive.
Part of Thinking Partner Phase 2.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add Integration Tests

**Files:**
- Create: `SeleneChat/Tests/SeleneChatTests/Integration/ThinkingPartnerContextIntegrationTests.swift`

**Step 1: Write integration tests**

```swift
import XCTest
@testable import SeleneChat

final class ThinkingPartnerContextIntegrationTests: XCTestCase {

    /// Test that context builder produces valid context for each query type
    func testAllQueryTypesProduceValidContext() {
        let builder = ThinkingPartnerContextBuilder()

        let thread = Thread(
            id: 1,
            name: "Test Thread",
            why: "Test reason",
            summary: "Test summary",
            status: "active",
            noteCount: 2,
            momentumScore: 0.5,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        let note = Note(id: 1, title: "Test Note", content: "Test content", createdAt: Date())

        // Briefing
        let briefingContext = builder.buildBriefingContext(threads: [thread], recentNotes: [note])
        XCTAssertFalse(briefingContext.isEmpty)
        XCTAssertTrue(builder.estimateTokens(briefingContext) <= ThinkingPartnerQueryType.briefing.tokenBudget)

        // Synthesis
        let synthesisContext = builder.buildSynthesisContext(threads: [thread], notesPerThread: [1: [note]])
        XCTAssertFalse(synthesisContext.isEmpty)
        XCTAssertTrue(builder.estimateTokens(synthesisContext) <= ThinkingPartnerQueryType.synthesis.tokenBudget)

        // Deep-dive
        let deepDiveContext = builder.buildDeepDiveContext(thread: thread, notes: [note])
        XCTAssertFalse(deepDiveContext.isEmpty)
        XCTAssertTrue(builder.estimateTokens(deepDiveContext) <= ThinkingPartnerQueryType.deepDive.tokenBudget)
    }

    /// Test that empty inputs produce graceful output
    func testEmptyInputsHandledGracefully() {
        let builder = ThinkingPartnerContextBuilder()

        // Empty briefing
        let briefingContext = builder.buildBriefingContext(threads: [], recentNotes: [])
        XCTAssertTrue(briefingContext.contains("Active Threads"))  // Header still present

        // Empty synthesis
        let synthesisContext = builder.buildSynthesisContext(threads: [], notesPerThread: [:])
        XCTAssertTrue(synthesisContext.contains("Prioritization"))

        // Deep-dive with no notes
        let thread = Thread(
            id: 1,
            name: "Empty Thread",
            why: nil,
            summary: nil,
            status: "active",
            noteCount: 0,
            momentumScore: nil,
            lastActivityAt: nil,
            createdAt: Date()
        )
        let deepDiveContext = builder.buildDeepDiveContext(thread: thread, notes: [])
        XCTAssertTrue(deepDiveContext.contains("Empty Thread"))
    }

    /// Test token budgets are respected under load
    func testTokenBudgetsUnderLoad() {
        let builder = ThinkingPartnerContextBuilder()

        // Create many threads and notes
        var threads: [Thread] = []
        var notesPerThread: [Int64: [Note]] = [:]

        for i in 0..<30 {
            let threadId = Int64(i)
            threads.append(Thread(
                id: threadId,
                name: "Thread \(i) with a long descriptive name",
                why: "Detailed reason for thread \(i) existence",
                summary: "Comprehensive summary of thread \(i) covering multiple topics and ideas",
                status: "active",
                noteCount: 10,
                momentumScore: Double(30 - i) / 30.0,
                lastActivityAt: Date(),
                createdAt: Date()
            ))

            var notes: [Note] = []
            for j in 0..<10 {
                notes.append(Note(
                    id: i * 10 + j,
                    title: "Note \(j) for Thread \(i)",
                    content: String(repeating: "Content for note \(j). ", count: 10),
                    createdAt: Date()
                ))
            }
            notesPerThread[threadId] = notes
        }

        // All context types should respect their budgets
        let briefing = builder.buildBriefingContext(threads: threads, recentNotes: notesPerThread[0] ?? [])
        XCTAssertLessThanOrEqual(builder.estimateTokens(briefing), ThinkingPartnerQueryType.briefing.tokenBudget)

        let synthesis = builder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)
        XCTAssertLessThanOrEqual(builder.estimateTokens(synthesis), ThinkingPartnerQueryType.synthesis.tokenBudget)

        let deepDive = builder.buildDeepDiveContext(thread: threads[0], notes: notesPerThread[0] ?? [])
        XCTAssertLessThanOrEqual(builder.estimateTokens(deepDive), ThinkingPartnerQueryType.deepDive.tokenBudget)
    }
}
```

**Step 2: Run tests**

Run: `cd /Users/chaseeasterling/selene/SeleneChat && swift test --filter ThinkingPartnerContextIntegrationTests`
Expected: PASS

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene
git add SeleneChat/Tests/SeleneChatTests/Integration/ThinkingPartnerContextIntegrationTests.swift
git commit -m "$(cat <<'EOF'
test(selenechat): add ThinkingPartnerContextBuilder integration tests

Verifies all query types produce valid context within token budgets.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `docs/plans/2026-02-05-selene-thinking-partner-design.md`
- Modify: `.claude/PROJECT-STATUS.md`

**Step 1: Update design doc**

Mark Phase 2 as complete:

```markdown
### Phase 2: Context Builder ✅ COMPLETE

**Components:**
- `ThinkingPartnerQueryType` enum - briefing, synthesis, deepDive with token budgets
- `ThinkingPartnerContextBuilder` service - assembles thread-focused context
- `buildBriefingContext()` - threads + momentum + recent notes
- `buildSynthesisContext()` - cross-thread comparison with note titles
- `buildDeepDiveContext()` - full thread with chronological notes

**Acceptance Criteria:**
- [x] Briefing context includes threads + momentum + recent notes
- [x] Synthesis context includes cross-thread data
- [x] Deep-dive context includes full thread history
- [x] Never exceeds context window (token budget enforcement)
```

**Step 2: Update PROJECT-STATUS.md**

Add achievement entry:

```markdown
### 2026-02-05
- **Thinking Partner Phase 2 Complete** - Context Builder
  - `ThinkingPartnerQueryType` enum with token budgets
  - `ThinkingPartnerContextBuilder` service
  - `buildBriefingContext()` - threads by momentum + recent notes
  - `buildSynthesisContext()` - cross-thread with note titles
  - `buildDeepDiveContext()` - full thread + chronological notes
  - Token budget enforcement for all context types
  - Integration tests verifying budget compliance
```

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene
git add docs/plans/2026-02-05-selene-thinking-partner-design.md .claude/PROJECT-STATUS.md
git commit -m "$(cat <<'EOF'
docs: mark Thinking Partner Phase 2 complete

- ThinkingPartnerQueryType enum with token budgets
- ThinkingPartnerContextBuilder with briefing/synthesis/deep-dive
- Token budget enforcement tested

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Acceptance Criteria Verification

After completing all tasks, verify:

- [x] **Briefing context includes threads + momentum + recent notes**
  - Verified in: Task 3 tests

- [x] **Synthesis context includes cross-thread data**
  - Verified in: Task 4 tests

- [x] **Deep-dive context includes full thread history**
  - Verified in: Task 5 tests

- [x] **Never exceeds context window**
  - Verified in: Task 6 integration tests (token budget under load)

---

## Summary

**Files Created:**
- `SeleneChat/Sources/Models/ThinkingPartnerQueryType.swift`
- `SeleneChat/Sources/Services/ThinkingPartnerContextBuilder.swift`
- `SeleneChat/Tests/SeleneChatTests/Models/ThinkingPartnerQueryTypeTests.swift`
- `SeleneChat/Tests/SeleneChatTests/Services/ThinkingPartnerContextBuilderTests.swift`
- `SeleneChat/Tests/SeleneChatTests/Integration/ThinkingPartnerContextIntegrationTests.swift`

**Files Modified:**
- `docs/plans/2026-02-05-selene-thinking-partner-design.md`
- `.claude/PROJECT-STATUS.md`

**Total Commits:** 7
