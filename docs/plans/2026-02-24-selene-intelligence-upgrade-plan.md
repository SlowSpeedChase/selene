# Selene Intelligence Upgrade — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform Selene's chat from generic summarizer into a minimal, evidence-citing thinking partner by improving context retrieval and rewriting all system prompts.

**Architecture:** Layer 1 (enhanced retrieval) adds new database queries and a `ContextualRetriever` service that assembles labeled context blocks (emotional history, decision history, task outcomes, thread state). Layer 2 (prompt rewrite) rewrites every system prompt with Selene's zen personality and conversational rules. Both layers target the Swift SeleneChat package — no TypeScript backend changes needed.

**Tech Stack:** Swift 5.9+, SQLite.swift, XCTest, SeleneShared + SeleneChat targets

---

## Task 1: Add `essence` and `fidelity_tier` to Swift Note Model

The `processed_notes` table already has `essence` and `fidelity_tier` columns (migration 020), but the Swift `Note` model doesn't read them. This is a prerequisite for contextual retrieval — essences are compact representations used in summary-tier context blocks.

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Models/Note.swift`
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Models/NoteModelTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Models/NoteModelTests.swift
import XCTest
import SeleneShared

final class NoteEssenceTests: XCTestCase {
    func testNoteHasEssenceProperty() {
        let note = Note.mock(
            essence: "Core insight about morning routines",
            fidelityTier: "summary"
        )
        XCTAssertEqual(note.essence, "Core insight about morning routines")
        XCTAssertEqual(note.fidelityTier, "summary")
    }

    func testNoteEssenceDefaultsToNil() {
        let note = Note.mock()
        XCTAssertNil(note.essence)
        XCTAssertNil(note.fidelityTier)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter NoteEssenceTests 2>&1 | tail -20`
Expected: FAIL — `Note.mock` doesn't accept `essence` or `fidelityTier` parameters

**Step 3: Add `essence` and `fidelityTier` to Note model**

In `Sources/SeleneShared/Models/Note.swift`:

Add properties after `energyLevel`:
```swift
public var essence: String?
public var fidelityTier: String?
```

Add CodingKeys:
```swift
case essence
case fidelityTier = "fidelity_tier"
```

Add to `init(...)` parameter list and body. Add to `init(from decoder:)`. Add to `#if DEBUG mock()` factory.

**Step 4: Add essence column read to DatabaseService**

In `Sources/SeleneChat/Services/DatabaseService.swift`, add column expressions:
```swift
private let essence = Expression<String?>("essence")
private let fidelityTier = Expression<String?>("fidelity_tier")
```

In the `noteFromRow(_:)` method (or wherever `Note` is constructed from a row), add:
```swift
essence: try? row.get(processedNotes[essence]),
fidelityTier: try? row.get(processedNotes[fidelityTier]),
```

**Step 5: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter NoteEssenceTests 2>&1 | tail -20`
Expected: PASS

**Step 6: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Models/Note.swift SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift SeleneChat/Tests/SeleneChatTests/Models/NoteModelTests.swift
git commit -m "feat: add essence and fidelity_tier to Swift Note model"
```

---

## Task 2: Add `threadDigest` and `emotionalCharge` to Swift Thread Model

Same pattern — `threads` table has `thread_digest` and `emotional_charge` but the Swift model doesn't read them.

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Models/Thread.swift`
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Models/ThreadModelTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Models/ThreadModelTests.swift
import XCTest
import SeleneShared

final class ThreadDigestTests: XCTestCase {
    func testThreadHasDigestProperty() {
        let thread = Thread.mock(
            threadDigest: "This thread started as exploration of morning routines and evolved into a daily habits system.",
            emotionalCharge: "motivated"
        )
        XCTAssertEqual(thread.threadDigest, "This thread started as exploration of morning routines and evolved into a daily habits system.")
        XCTAssertEqual(thread.emotionalCharge, "motivated")
    }

    func testThreadDigestDefaultsToNil() {
        let thread = Thread.mock()
        XCTAssertNil(thread.threadDigest)
        XCTAssertNil(thread.emotionalCharge)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ThreadDigestTests 2>&1 | tail -20`
Expected: FAIL

**Step 3: Add properties to Thread model**

In `Sources/SeleneShared/Models/Thread.swift`, add:
```swift
public let threadDigest: String?
public let emotionalCharge: String?
```

Update `init(...)`, `mock()`. No `Codable` needed — Thread isn't Codable, it's constructed from SQLite rows directly.

**Step 4: Add column reads to DatabaseService**

Add column expressions and read them in the thread construction code. Search for where `Thread(` is constructed in DatabaseService.

**Step 5: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ThreadDigestTests 2>&1 | tail -20`
Expected: PASS

**Step 6: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Models/Thread.swift SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift SeleneChat/Tests/SeleneChatTests/Models/ThreadModelTests.swift
git commit -m "feat: add threadDigest and emotionalCharge to Swift Thread model"
```

---

## Task 3: Add Emotional History Query to DatabaseService

New query: find notes where the user expressed strong emotion about a topic. Uses existing `emotional_tone` and `sentiment_score` columns on `processed_notes`, filtered by keyword relevance.

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`
- Modify: `SeleneChat/Sources/SeleneShared/Protocols/DataProvider.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/EmotionalHistoryQueryTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/EmotionalHistoryQueryTests.swift
import XCTest
import SeleneShared
@testable import SeleneChat

final class EmotionalHistoryQueryTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path
        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    func testGetEmotionalNotesReturnsStrongEmotions() async throws {
        // This test verifies the method signature compiles and returns [Note]
        // Actual data testing requires seeded DB rows
        let notes = try await databaseService.getEmotionalNotes(
            keywords: ["morning", "routine"],
            limit: 5
        )
        XCTAssertNotNil(notes)
        // Empty DB returns empty array
        XCTAssertTrue(notes.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter EmotionalHistoryQueryTests 2>&1 | tail -20`
Expected: FAIL — `getEmotionalNotes` doesn't exist

**Step 3: Add to DataProvider protocol**

In `Sources/SeleneShared/Protocols/DataProvider.swift`, add under `// MARK: - Notes`:
```swift
/// Find notes with strong emotional signals related to keywords
func getEmotionalNotes(keywords: [String], limit: Int) async throws -> [Note]
```

**Step 4: Implement in DatabaseService**

```swift
func getEmotionalNotes(keywords: [String], limit: Int = 5) async throws -> [Note] {
    guard let db = db else { throw DatabaseError.notConnected }

    // Find notes with non-neutral emotional tone that match keywords
    // emotional_tone values: excited, calm, anxious, frustrated, happy, sad, neutral
    // sentiment_score: -1.0 to 1.0 (strong signals are > 0.5 or < -0.5)
    let keywordClauses = keywords.map { kw in
        "r.content LIKE '%' || '\(kw.replacingOccurrences(of: "'", with: "''"))' || '%'"
    }.joined(separator: " OR ")

    guard !keywordClauses.isEmpty else { return [] }

    let sql = """
        SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
               p.secondary_themes, p.theme_confidence, p.overall_sentiment,
               p.sentiment_score, p.emotional_tone, p.energy_level,
               p.essence, p.fidelity_tier
        FROM raw_notes r
        LEFT JOIN processed_notes p ON r.id = p.raw_note_id
        WHERE (\(keywordClauses))
          AND p.emotional_tone IS NOT NULL
          AND p.emotional_tone != 'neutral'
          AND r.test_run IS NULL
        ORDER BY ABS(p.sentiment_score) DESC, r.created_at DESC
        LIMIT ?
    """

    let stmt = try db.prepare(sql)
    var notes: [Note] = []
    for row in try stmt.bind(limit) {
        if let note = try? noteFromRow(row) {
            notes.append(note)
        }
    }
    return notes
}
```

Note: The exact SQL binding pattern may need adjustment to match `DatabaseService`'s existing raw SQL patterns. Check how other raw SQL queries are done in that file and follow the same pattern.

**Step 5: Add stub to RemoteDataService (iOS)**

In `Sources/SeleneMobile/Services/RemoteDataService.swift`, add:
```swift
func getEmotionalNotes(keywords: [String], limit: Int) async throws -> [Note] {
    // TODO: Add server endpoint when needed
    return []
}
```

**Step 6: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter EmotionalHistoryQueryTests 2>&1 | tail -20`
Expected: PASS

**Step 7: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Protocols/DataProvider.swift SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift SeleneChat/Sources/SeleneMobile/Services/RemoteDataService.swift SeleneChat/Tests/SeleneChatTests/Services/EmotionalHistoryQueryTests.swift
git commit -m "feat: add emotional history query to DatabaseService"
```

---

## Task 4: Add Task Outcome Query to DatabaseService

New query: find completed, abandoned, or overdue tasks related to a topic. Uses `task_metadata` table joined with `raw_notes` for keyword matching.

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`
- Modify: `SeleneChat/Sources/SeleneShared/Protocols/DataProvider.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/TaskOutcomeQueryTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/TaskOutcomeQueryTests.swift
import XCTest
import SeleneShared
@testable import SeleneChat

final class TaskOutcomeQueryTests: XCTestCase {
    func testGetTaskOutcomesReturnsTypedResults() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path
        let databaseService = DatabaseService()
        databaseService.databasePath = testPath

        defer { try? FileManager.default.removeItem(atPath: testPath) }

        let outcomes = try await databaseService.getTaskOutcomes(
            keywords: ["morning", "routine"],
            limit: 10
        )
        XCTAssertNotNil(outcomes)
        XCTAssertTrue(outcomes.isEmpty) // Empty DB
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter TaskOutcomeQueryTests 2>&1 | tail -20`
Expected: FAIL — `getTaskOutcomes` doesn't exist

**Step 3: Define TaskOutcome model**

Create in `Sources/SeleneShared/Models/TaskOutcome.swift`:
```swift
import Foundation

/// Summary of a task's lifecycle for contextual retrieval
public struct TaskOutcome: Hashable {
    public let taskTitle: String
    public let taskType: String?          // action/decision/research/communication/learning/planning
    public let energyRequired: String?    // high/medium/low
    public let estimatedMinutes: Int?
    public let status: String             // completed/abandoned/open
    public let createdAt: Date
    public let completedAt: Date?
    public let daysOpen: Int              // how long from creation to now or completion

    public init(taskTitle: String, taskType: String?, energyRequired: String?,
                estimatedMinutes: Int?, status: String, createdAt: Date,
                completedAt: Date?, daysOpen: Int) {
        self.taskTitle = taskTitle
        self.taskType = taskType
        self.energyRequired = energyRequired
        self.estimatedMinutes = estimatedMinutes
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.daysOpen = daysOpen
    }
}
```

**Step 4: Add to DataProvider protocol and implement**

In `DataProvider.swift`:
```swift
func getTaskOutcomes(keywords: [String], limit: Int) async throws -> [TaskOutcome]
```

In `DatabaseService.swift`, query `task_metadata` joined with `raw_notes`:
```swift
func getTaskOutcomes(keywords: [String], limit: Int = 10) async throws -> [TaskOutcome] {
    guard let db = db else { throw DatabaseError.notConnected }
    guard !keywords.isEmpty else { return [] }

    let keywordClauses = keywords.map { kw in
        "(r.content LIKE '%' || '\(kw.replacingOccurrences(of: "'", with: "''"))' || '%' OR tm.related_concepts LIKE '%' || '\(kw.replacingOccurrences(of: "'", with: "''"))' || '%')"
    }.joined(separator: " OR ")

    let sql = """
        SELECT tm.things_task_id, tm.task_type, tm.energy_required,
               tm.estimated_minutes, tm.created_at, tm.completed_at,
               r.title
        FROM task_metadata tm
        LEFT JOIN raw_notes r ON tm.raw_note_id = r.id
        WHERE (\(keywordClauses))
          AND r.test_run IS NULL
        ORDER BY tm.created_at DESC
        LIMIT ?
    """

    var outcomes: [TaskOutcome] = []
    let stmt = try db.prepare(sql)
    for row in try stmt.bind(limit) {
        let createdAt = /* parse date from row */
        let completedAt = /* parse optional date */
        let status: String
        if completedAt != nil { status = "completed" }
        else {
            let daysSinceCreation = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
            status = daysSinceCreation > 30 ? "abandoned" : "open"
        }
        outcomes.append(TaskOutcome(
            taskTitle: row[...] ?? "Untitled task",
            taskType: row[...],
            energyRequired: row[...],
            estimatedMinutes: row[...],
            status: status,
            createdAt: createdAt,
            completedAt: completedAt,
            daysOpen: Calendar.current.dateComponents([.day], from: createdAt, to: completedAt ?? Date()).day ?? 0
        ))
    }
    return outcomes
}
```

Note: Adapt the row-access pattern to match how `DatabaseService` handles raw SQL results elsewhere. The exact syntax depends on whether `sqlite3_stmt` or SQLite.swift's `Statement` is used.

**Step 5: Stub in RemoteDataService**

```swift
func getTaskOutcomes(keywords: [String], limit: Int) async throws -> [TaskOutcome] { return [] }
```

**Step 6: Run tests, verify pass, commit**

Run: `cd SeleneChat && swift test --filter TaskOutcomeQueryTests 2>&1 | tail -20`

```bash
git add SeleneChat/Sources/SeleneShared/Models/TaskOutcome.swift SeleneChat/Sources/SeleneShared/Protocols/DataProvider.swift SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift SeleneChat/Sources/SeleneMobile/Services/RemoteDataService.swift SeleneChat/Tests/SeleneChatTests/Services/TaskOutcomeQueryTests.swift
git commit -m "feat: add task outcome query for contextual retrieval"
```

---

## Task 5: Add Sentiment Trend Aggregation Query

New query: compute emotional tone distribution over a time window (e.g., "this week: frustrated 4x, anxious 2x, calm 1x"). No new table — aggregates from existing `processed_notes.emotional_tone`.

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`
- Modify: `SeleneChat/Sources/SeleneShared/Protocols/DataProvider.swift`
- Create: `SeleneChat/Sources/SeleneShared/Models/SentimentTrend.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/SentimentTrendQueryTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/SentimentTrendQueryTests.swift
import XCTest
import SeleneShared
@testable import SeleneChat

final class SentimentTrendQueryTests: XCTestCase {
    func testGetSentimentTrendReturnsAggregation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path
        let databaseService = DatabaseService()
        databaseService.databasePath = testPath
        defer { try? FileManager.default.removeItem(atPath: testPath) }

        let trend = try await databaseService.getSentimentTrend(days: 7)
        XCTAssertNotNil(trend)
        XCTAssertTrue(trend.toneCounts.isEmpty) // Empty DB
        XCTAssertEqual(trend.totalNotes, 0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter SentimentTrendQueryTests 2>&1 | tail -20`
Expected: FAIL

**Step 3: Create SentimentTrend model**

```swift
// Sources/SeleneShared/Models/SentimentTrend.swift
import Foundation

public struct SentimentTrend: Hashable {
    /// e.g. ["frustrated": 4, "anxious": 2, "calm": 1]
    public let toneCounts: [String: Int]
    public let totalNotes: Int
    public let averageSentimentScore: Double?
    public let periodDays: Int

    public init(toneCounts: [String: Int], totalNotes: Int,
                averageSentimentScore: Double?, periodDays: Int) {
        self.toneCounts = toneCounts
        self.totalNotes = totalNotes
        self.averageSentimentScore = averageSentimentScore
        self.periodDays = periodDays
    }

    /// Most frequent non-neutral tone, if any
    public var dominantTone: String? {
        toneCounts.filter { $0.key != "neutral" }.max(by: { $0.value < $1.value })?.key
    }

    /// Format for context injection: "frustrated 4x, anxious 2x"
    public var formatted: String {
        let sorted = toneCounts.filter { $0.key != "neutral" }
            .sorted { $0.value > $1.value }
        guard !sorted.isEmpty else { return "mostly neutral" }
        return sorted.map { "\($0.key) \($0.value)x" }.joined(separator: ", ")
    }
}
```

**Step 4: Add to DataProvider and implement**

Protocol:
```swift
func getSentimentTrend(days: Int) async throws -> SentimentTrend
```

DatabaseService:
```sql
SELECT p.emotional_tone, COUNT(*) as cnt, AVG(p.sentiment_score) as avg_score
FROM processed_notes p
JOIN raw_notes r ON p.raw_note_id = r.id
WHERE r.created_at >= datetime('now', '-' || ? || ' days')
  AND r.test_run IS NULL
  AND p.emotional_tone IS NOT NULL
GROUP BY p.emotional_tone
```

Aggregate into `SentimentTrend(toneCounts:totalNotes:averageSentimentScore:periodDays:)`.

**Step 5: Stub in RemoteDataService, run tests, commit**

```bash
git commit -m "feat: add sentiment trend aggregation query"
```

---

## Task 6: Create ContextualRetriever Service

The core of Layer 1. Orchestrates multi-signal retrieval and assembles labeled context blocks for injection into LLM prompts.

**Files:**
- Create: `SeleneChat/Sources/SeleneShared/Services/ContextualRetriever.swift`
- Create: `SeleneChat/Sources/SeleneShared/Models/RetrievedContext.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ContextualRetrieverTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/ContextualRetrieverTests.swift
import XCTest
import SeleneShared
@testable import SeleneChat

@MainActor
final class ContextualRetrieverTests: XCTestCase {

    func testRetrieveContextReturnsLabeledBlocks() async throws {
        // Use a mock DataProvider that returns canned data
        let mockProvider = MockDataProvider()
        mockProvider.emotionalNotes = [
            Note.mock(id: 1, title: "Frustrated morning", content: "I keep failing at morning routines",
                      createdAt: Date(), emotionalTone: "frustrated", sentimentScore: -0.7)
        ]
        mockProvider.sentimentTrend = SentimentTrend(
            toneCounts: ["frustrated": 3, "anxious": 1],
            totalNotes: 10,
            averageSentimentScore: -0.3,
            periodDays: 7
        )

        let retriever = ContextualRetriever(dataProvider: mockProvider)
        let context = try await retriever.retrieve(
            query: "help me with morning routines",
            keywords: ["morning", "routine"]
        )

        XCTAssertFalse(context.blocks.isEmpty)
        // Should have at least an emotional history block and a sentiment trend block
        XCTAssertTrue(context.blocks.contains { $0.type == .emotionalHistory })
        XCTAssertTrue(context.blocks.contains { $0.type == .sentimentTrend })
    }

    func testFormattedContextContainsLabels() async throws {
        let block = ContextBlock(
            type: .emotionalHistory,
            content: "\"I keep failing at morning routines\"",
            sourceDate: Date(),
            sourceTitle: "Frustrated morning"
        )
        let context = RetrievedContext(blocks: [block])
        let formatted = context.formatted()

        XCTAssertTrue(formatted.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(formatted.contains("I keep failing"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ContextualRetrieverTests 2>&1 | tail -20`
Expected: FAIL — types don't exist

**Step 3: Create RetrievedContext model**

```swift
// Sources/SeleneShared/Models/RetrievedContext.swift
import Foundation

public enum ContextBlockType: String {
    case relevantNote = "RELEVANT NOTE"
    case emotionalHistory = "EMOTIONAL HISTORY"
    case decisionHistory = "DECISION"
    case taskHistory = "TASK HISTORY"
    case sentimentTrend = "EMOTIONAL TREND"
    case threadState = "THREAD STATE"
}

public struct ContextBlock: Hashable {
    public let type: ContextBlockType
    public let content: String
    public let sourceDate: Date?
    public let sourceTitle: String?

    public init(type: ContextBlockType, content: String,
                sourceDate: Date? = nil, sourceTitle: String? = nil) {
        self.type = type
        self.content = content
        self.sourceDate = sourceDate
        self.sourceTitle = sourceTitle
    }

    public var formatted: String {
        let dateStr: String
        if let date = sourceDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            dateStr = " - \(formatter.string(from: date))"
        } else {
            dateStr = ""
        }

        let titleStr = sourceTitle.map { " — \($0)" } ?? ""
        return "[\(type.rawValue)\(dateStr)\(titleStr)]: \(content)"
    }
}

public struct RetrievedContext {
    public let blocks: [ContextBlock]

    public init(blocks: [ContextBlock]) {
        self.blocks = blocks
    }

    /// Format all blocks for prompt injection
    public func formatted() -> String {
        blocks.map { $0.formatted }.joined(separator: "\n")
    }

    /// Estimate token count (4 chars per token)
    public var estimatedTokens: Int {
        formatted().count / 4
    }
}
```

**Step 4: Create ContextualRetriever service**

```swift
// Sources/SeleneShared/Services/ContextualRetriever.swift
import Foundation

/// Orchestrates multi-signal retrieval for chat context.
/// Assembles labeled context blocks from emotional history, task outcomes,
/// sentiment trends, and thread state.
public class ContextualRetriever {
    private let dataProvider: DataProvider
    private let tokenBudget: Int

    public init(dataProvider: DataProvider, tokenBudget: Int = 3000) {
        self.dataProvider = dataProvider
        self.tokenBudget = tokenBudget
    }

    /// Retrieve contextual blocks for a query.
    /// - Parameters:
    ///   - query: The user's message
    ///   - keywords: Extracted keywords from query analysis
    ///   - threadId: Optional thread scope
    /// - Returns: Labeled context blocks ready for prompt injection
    public func retrieve(
        query: String,
        keywords: [String],
        threadId: Int64? = nil
    ) async throws -> RetrievedContext {
        var blocks: [ContextBlock] = []
        var remainingTokens = tokenBudget

        // 1. Emotional history — notes with strong emotion on this topic
        let emotionalNotes = try await dataProvider.getEmotionalNotes(
            keywords: keywords, limit: 3
        )
        for note in emotionalNotes {
            let block = ContextBlock(
                type: .emotionalHistory,
                content: note.essence ?? String(note.content.prefix(200)),
                sourceDate: note.createdAt,
                sourceTitle: note.title
            )
            let tokens = block.formatted.count / 4
            guard remainingTokens - tokens > 0 else { break }
            blocks.append(block)
            remainingTokens -= tokens
        }

        // 2. Task outcomes — completed/abandoned tasks related to topic
        let taskOutcomes = try await dataProvider.getTaskOutcomes(
            keywords: keywords, limit: 5
        )
        if !taskOutcomes.isEmpty {
            let summary = taskOutcomes.map { outcome in
                let statusIcon = outcome.status == "completed" ? "done" : outcome.status
                return "\(outcome.taskTitle) (\(statusIcon), \(outcome.daysOpen)d)"
            }.joined(separator: "; ")

            let block = ContextBlock(
                type: .taskHistory,
                content: summary
            )
            let tokens = block.formatted.count / 4
            if remainingTokens - tokens > 0 {
                blocks.append(block)
                remainingTokens -= tokens
            }
        }

        // 3. Sentiment trend — emotional distribution this week
        let trend = try await dataProvider.getSentimentTrend(days: 7)
        if trend.totalNotes > 0 {
            let block = ContextBlock(
                type: .sentimentTrend,
                content: "This week (\(trend.totalNotes) notes): \(trend.formatted)"
            )
            let tokens = block.formatted.count / 4
            if remainingTokens - tokens > 0 {
                blocks.append(block)
                remainingTokens -= tokens
            }
        }

        // 4. Thread state — if scoped to a thread
        if let threadId = threadId,
           let thread = try await dataProvider.getThreadById(threadId) {
            let tasks = try await dataProvider.getTasksForThread(threadId)
            let openTasks = tasks.filter { !$0.isCompleted }
            let daysSinceActivity = thread.lastActivityAt.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 0

            let block = ContextBlock(
                type: .threadState,
                content: "'\(thread.name)' — \(thread.status), \(thread.noteCount) notes, \(openTasks.count) open tasks, last activity \(daysSinceActivity)d ago, momentum \(thread.momentumDisplay)"
            )
            let tokens = block.formatted.count / 4
            if remainingTokens - tokens > 0 {
                blocks.append(block)
                remainingTokens -= tokens
            }
        }

        return RetrievedContext(blocks: blocks)
    }
}
```

**Step 5: Create MockDataProvider for tests**

You'll need a `MockDataProvider` class in the test file that conforms to `DataProvider`, returning canned data for the methods under test and empty defaults for the rest. Follow the existing pattern of private mock classes inside test files (see `LLMRouterTests.swift` for reference).

**Step 6: Run tests, verify pass, commit**

Run: `cd SeleneChat && swift test --filter ContextualRetrieverTests 2>&1 | tail -20`

```bash
git add SeleneChat/Sources/SeleneShared/Models/RetrievedContext.swift SeleneChat/Sources/SeleneShared/Services/ContextualRetriever.swift SeleneChat/Tests/SeleneChatTests/Services/ContextualRetrieverTests.swift
git commit -m "feat: add ContextualRetriever service with labeled context blocks"
```

---

## Task 7: Integrate ContextualRetriever into ChatViewModel

Wire the new retrieval into the main chat flow. The `handleOllamaQuery` method should call `ContextualRetriever` and inject its output alongside the existing note context.

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/ContextualRetrievalIntegrationTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Integration/ContextualRetrievalIntegrationTests.swift
import XCTest
import SeleneShared
@testable import SeleneChat

final class ContextualRetrievalIntegrationTests: XCTestCase {

    func testRetrievedContextFormatsAsLabeledBlocks() {
        // Test that RetrievedContext formatting matches what we'd inject
        let blocks = [
            ContextBlock(type: .emotionalHistory, content: "Felt frustrated about morning routines",
                         sourceDate: Date(), sourceTitle: "Morning struggle"),
            ContextBlock(type: .taskHistory, content: "wake-up-early (abandoned, 12d); buy-alarm (done, 3d)"),
            ContextBlock(type: .sentimentTrend, content: "This week (8 notes): frustrated 3x, anxious 2x"),
        ]
        let context = RetrievedContext(blocks: blocks)
        let formatted = context.formatted()

        XCTAssertTrue(formatted.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(formatted.contains("[TASK HISTORY"))
        XCTAssertTrue(formatted.contains("[EMOTIONAL TREND"))
        XCTAssertTrue(formatted.contains("frustrated"))
    }
}
```

**Step 2: Run test to verify it passes** (this tests the model, not the integration — should pass from Task 6)

**Step 3: Modify ChatViewModel.handleOllamaQuery**

In `ChatViewModel.swift`, add a `contextualRetriever` property:
```swift
private lazy var contextualRetriever = ContextualRetriever(dataProvider: dataProvider)
```

In `handleOllamaQuery`, after the existing note retrieval (line ~344) and before building the full prompt (line ~377), add:

```swift
// Retrieve contextual blocks (emotional history, task outcomes, sentiment trends)
let contextualBlocks = try await contextualRetriever.retrieve(
    query: query,
    keywords: analysis.keywords
)
let contextualSection = contextualBlocks.blocks.isEmpty ? "" : """

## Context from your history:
\(contextualBlocks.formatted())

"""
```

Then inject `contextualSection` into the full prompt between `systemPrompt` and `Notes:`:

```swift
let fullPrompt = """
\(systemPrompt)
\(historySection)
\(contextualSection)
Notes:
\(noteContext)

Question: \(context)
"""
```

**Step 4: Run full test suite to verify no regressions**

Run: `cd SeleneChat && swift test 2>&1 | tail -30`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift SeleneChat/Tests/SeleneChatTests/Integration/ContextualRetrievalIntegrationTests.swift
git commit -m "feat: integrate ContextualRetriever into ChatViewModel chat flow"
```

---

## Task 8: Integrate ContextualRetriever into ThreadWorkspaceChatViewModel

Same integration for thread workspace chat. Thread workspace has an advantage: we know the `threadId`, so thread-scoped retrieval is more precise.

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/ViewModels/ThreadWorkspaceRetrievalTests.swift`

**Step 1: Write the failing test**

Test that `buildChunkBasedPrompt` now includes contextual blocks. Since the ViewModel calls OllamaService directly (not mockable without protocol injection), test the retriever formatting in isolation.

```swift
import XCTest
import SeleneShared

final class ThreadWorkspaceRetrievalTests: XCTestCase {
    func testContextBlocksIncludeThreadState() {
        let block = ContextBlock(
            type: .threadState,
            content: "'Morning Routine' — active, 8 notes, 2 open tasks, last activity 3d ago, momentum 0.7"
        )
        XCTAssertTrue(block.formatted.contains("[THREAD STATE]"))
        XCTAssertTrue(block.formatted.contains("Morning Routine"))
    }
}
```

**Step 2: Modify ThreadWorkspaceChatViewModel**

Add `contextualRetriever` property. In `buildChunkBasedPrompt`, after building the prompt from chunks/notes, prepend the contextual blocks section.

The thread workspace already has `thread`, `notes`, and `tasks` — pass `thread.id` to `retriever.retrieve(query:keywords:threadId:)`.

For keywords, extract from the query using simple word splitting (or reuse `QueryAnalyzer` if available).

**Step 3: Run tests, commit**

```bash
git commit -m "feat: integrate ContextualRetriever into ThreadWorkspaceChatViewModel"
```

---

## Task 9: Rewrite ChatViewModel System Prompts (Layer 2)

Replace the generic "helpful AI assistant" system prompt with Selene's zen personality and conversational rules. This is the most impactful single change.

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift` — `buildSystemPrompt(for:)` method
- Test: `SeleneChat/Tests/SeleneChatTests/Services/SystemPromptTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/SystemPromptTests.swift
import XCTest
import SeleneShared
@testable import SeleneChat

@MainActor
final class SystemPromptTests: XCTestCase {

    func testSystemPromptContainsZenPersonality() {
        let vm = ChatViewModel()
        // Access the prompt via a helper or test the string directly
        // We'll test the prompt builder output
        let prompt = vm.buildSystemPromptForTesting(queryType: .general)

        // Should NOT contain old generic language
        XCTAssertFalse(prompt.contains("personal AI assistant"))
        XCTAssertFalse(prompt.contains("Be conversational and supportive"))

        // Should contain zen personality markers
        XCTAssertTrue(prompt.contains("Never summarize unless asked"))
        XCTAssertTrue(prompt.contains("Cite specific notes"))
    }

    func testSystemPromptContainsCitationEvidence() {
        let vm = ChatViewModel()
        let prompt = vm.buildSystemPromptForTesting(queryType: .knowledge)

        XCTAssertTrue(prompt.contains("cite") || prompt.contains("Cite"))
        XCTAssertTrue(prompt.contains("evidence") || prompt.contains("specific notes"))
    }
}
```

Note: You may need to add a `buildSystemPromptForTesting` method (or make `buildSystemPrompt` internal instead of private) to enable testing. Use `@testable import` access.

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter SystemPromptTests 2>&1 | tail -20`
Expected: FAIL — old prompt doesn't match new assertions

**Step 3: Rewrite `buildSystemPrompt(for:)`**

Replace the entire method body in `ChatViewModel.swift` (lines 732-784):

```swift
private func buildSystemPrompt(for queryType: QueryAnalyzer.QueryType) -> String {
    var prompt = """
    You are Selene. Minimal. Precise. Kind.

    RULES:
    - Never summarize unless asked. Engage.
    - If the user wants help: ask 1-2 questions first. Understand what they're stuck on before responding.
    - Cite specific notes by title and date. Never say "based on your notes" generically.
    - Present 2-3 options with tradeoffs when the user faces a decision.
    - If context shows repeated patterns or failed attempts: name them directly. Kindly.
    - End by asking what resonates. Never end with a monologue.
    - Short sentences. No filler. Every word earns its place.

    CONTEXT BLOCKS:
    You may receive labeled context like [EMOTIONAL HISTORY], [TASK HISTORY], [EMOTIONAL TREND], [THREAD STATE].
    Use these to ground your response in evidence. Reference them naturally — don't list them back.

    """

    // Query-specific additions
    switch queryType {
    case .pattern:
        prompt += "\nFOCUS: Identify patterns across these notes. Name tensions. Ask what the user sees.\n"
    case .search:
        prompt += "\nFOCUS: Surface what's relevant. Cite specific notes. Ask if this is what they're looking for.\n"
    case .knowledge:
        prompt += "\nFOCUS: Answer from note evidence. Cite sources. If the answer isn't in the notes, say so.\n"
    case .general:
        prompt += "\nFOCUS: Engage with what's on their mind. Use context blocks to ground the conversation.\n"
    case .thread:
        prompt += "\nFOCUS: Show what's emerging across threads. Name connections. Ask where to focus.\n"
    case .semantic:
        prompt += "\nFOCUS: These notes are conceptually connected. Name the connection. Ask if it resonates.\n"
    case .deepDive:
        prompt += "\nFOCUS: Go deep on this thread. Identify tensions, open questions, next actions. Use [ACTION: description | ENERGY: level | TIMEFRAME: time] for actionable items.\n"
    case .synthesis:
        prompt += "\nFOCUS: Cross-thread synthesis. What patterns connect different lines of thinking? What deserves energy right now?\n"
    }

    return prompt
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter SystemPromptTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Run full test suite**

Run: `cd SeleneChat && swift test 2>&1 | tail -30`

**Step 6: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift SeleneChat/Tests/SeleneChatTests/Services/SystemPromptTests.swift
git commit -m "feat: rewrite ChatViewModel system prompts with zen personality"
```

---

## Task 10: Rewrite ThreadWorkspacePromptBuilder

Replace the existing system identity and all prompt templates with the zen personality, ensuring consistency between standard chat and thread workspace.

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Services/ThreadWorkspacePromptBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ThreadWorkspacePromptBuilderTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/ThreadWorkspacePromptBuilderTests.swift
import XCTest
import SeleneShared

final class ThreadWorkspacePromptRewriteTests: XCTestCase {

    func testSystemIdentityIsZen() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Morning Routine"),
            notes: [Note.mock()],
            tasks: []
        )

        // Should NOT contain old verbose instructions
        XCTAssertFalse(prompt.contains("Be concise but thorough"))
        XCTAssertFalse(prompt.contains("200 words"))

        // Should contain zen markers
        XCTAssertTrue(prompt.contains("Never summarize unless asked") || prompt.contains("Every word earns its place"))
    }

    func testWhatsNextPromptPresentsOptions() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildWhatsNextPrompt(
            thread: Thread.mock(name: "Morning Routine"),
            notes: [Note.mock()],
            tasks: [ThreadTask.mock()]
        )

        XCTAssertTrue(prompt.contains("2-3"))
        XCTAssertTrue(prompt.contains("trade-off") || prompt.contains("tradeoff"))
    }

    func testPlanningPromptAsksQuestionsFirst() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildPlanningPrompt(
            thread: Thread.mock(name: "Career"),
            notes: [],
            tasks: [],
            userQuery: "help me figure this out"
        )

        XCTAssertTrue(prompt.contains("ask") || prompt.contains("Ask"))
        XCTAssertTrue(prompt.contains("question") || prompt.contains("clarif"))
    }
}
```

**Step 2: Run test to verify it fails**

**Step 3: Rewrite systemIdentity and all prompt methods**

Replace `systemIdentity` with:
```swift
private let systemIdentity = """
You are Selene. Minimal. Precise. Kind.

RULES:
- Never summarize the thread unless asked. The user can see it.
- If they ask for help: ask 1-2 questions first. What are they stuck on?
- Cite specific notes by content. Never reference notes generically.
- Present 2-3 options with tradeoffs when they face a decision.
- If context shows repeated patterns or failed attempts: name them. Kindly.
- End by asking what resonates.

CONTEXT BLOCKS:
You may receive labeled context like [EMOTIONAL HISTORY], [TASK HISTORY], [EMOTIONAL TREND], [THREAD STATE].
Use these as evidence. Reference them naturally.

CAPABILITIES:
- Create tasks in Things via action markers:
  [ACTION: Brief description | ENERGY: high/medium/low | TIMEFRAME: today/this-week/someday]
- Full access to the user's notes, thread history, and existing tasks
"""
```

Update `buildPlanningPrompt` to use zen voice. Update `buildWhatsNextPrompt` similarly. Remove all hardcoded word limits.

**Step 4: Run tests, verify pass, commit**

```bash
git commit -m "feat: rewrite ThreadWorkspacePromptBuilder with zen personality"
```

---

## Task 11: Expand Planning Intent Detection

Expand `whatsNextPatterns` and `planningPatterns` to cover 30+ patterns total, catching more natural ways users express planning intent.

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Services/ThreadWorkspacePromptBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/PlanningIntentDetectionTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/PlanningIntentDetectionTests.swift
import XCTest
import SeleneShared

final class PlanningIntentDetectionTests: XCTestCase {
    let builder = ThreadWorkspacePromptBuilder()

    func testWhatsNextPatterns() {
        let queries = [
            "what's next", "what should I focus on", "what needs my attention",
            "what's most important", "what am I missing", "what's stalled"
        ]
        for query in queries {
            XCTAssertTrue(builder.isWhatsNextQuery(query), "Should detect: '\(query)'")
        }
    }

    func testPlanningPatterns() {
        let queries = [
            "help me think through this", "I'm stuck", "I don't know where to start",
            "what would you recommend", "talk me through this", "I'm overwhelmed",
            "I keep putting this off", "why am I avoiding this", "break this into pieces",
            "what's the simplest first step", "how do I even begin"
        ]
        for query in queries {
            XCTAssertTrue(builder.isPlanningQuery(query), "Should detect: '\(query)'")
        }
    }

    func testNonPlanningQueriesNotDetected() {
        let queries = [
            "show me notes about cooking", "when did I write about travel",
            "what's the weather"
        ]
        for query in queries {
            XCTAssertFalse(builder.isPlanningQuery(query), "Should NOT detect: '\(query)'")
        }
    }
}
```

**Step 2: Run test to verify it fails** — new patterns won't match

**Step 3: Expand pattern lists**

Add to `whatsNextPatterns`:
```swift
"what should i focus on", "what needs my attention", "what needs attention",
"what's most important", "what am i missing", "what's stalled",
"what's stuck", "where should i focus", "what deserves energy",
```

Add to `planningPatterns`:
```swift
"i'm stuck", "im stuck", "i don't know where to start",
"don't know where to start", "what would you recommend",
"talk me through", "i'm overwhelmed", "im overwhelmed",
"i keep putting this off", "keep avoiding", "why am i avoiding",
"what's the simplest", "simplest first step", "how do i even begin",
"how do i begin", "break this into pieces", "break this into steps",
"what's blocking", "what blocks", "where's the resistance",
```

**Step 4: Run tests, verify pass, commit**

```bash
git commit -m "feat: expand planning intent detection to 30+ patterns"
```

---

## Task 12: Align DeepDive and Synthesis Prompt Builders

Update the remaining prompt builders to match the zen personality. Remove word limits. Add context block awareness.

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Services/DeepDivePromptBuilder.swift`
- Modify: `SeleneChat/Sources/SeleneShared/Services/SynthesisPromptBuilder.swift`
- Modify: `SeleneChat/Sources/SeleneShared/Services/BriefingContextBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/PromptVoiceAlignmentTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/SeleneChatTests/Services/PromptVoiceAlignmentTests.swift
import XCTest
import SeleneShared

final class PromptVoiceAlignmentTests: XCTestCase {
    func testDeepDiveNoWordLimit() {
        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(),
            notes: [Note.mock()]
        )
        XCTAssertFalse(prompt.contains("200 words"))
        XCTAssertFalse(prompt.contains("150 words"))
        XCTAssertFalse(prompt.contains("100 words"))
    }

    func testSynthesisNoWordLimit() {
        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(
            threads: [Thread.mock()],
            notesPerThread: [1: [Note.mock()]]
        )
        XCTAssertFalse(prompt.contains("200 words"))
    }

    func testBriefingUsesZenVoice() {
        let builder = BriefingContextBuilder()
        let prompt = builder.buildSystemPrompt(for: .whatChanged)
        // Should ask a question, not summarize
        XCTAssertTrue(prompt.lowercased().contains("ask") || prompt.lowercased().contains("question"))
    }
}
```

**Step 2: Run test to verify it fails**

**Step 3: Update all three builders**

- `DeepDivePromptBuilder`: Remove "Keep response under 200 words" / "150 words". Replace intro text with zen voice. Keep the structural instructions (synthesize, identify tensions, ask questions).
- `SynthesisPromptBuilder`: Remove "200 words" limit. Replace "Recommended Focus:" format with open-ended options presentation.
- `BriefingContextBuilder`: Align `buildSystemPrompt(for:)` with zen voice. Keep the "ask a specific question" instruction (already good).

**Step 4: Run tests, full suite, commit**

```bash
git commit -m "feat: align DeepDive, Synthesis, and Briefing prompts with zen voice"
```

---

## Task 13: Full Integration Test — End-to-End Prompt Assembly

Test that a complete prompt (system + contextual blocks + notes + question) assembles correctly with all the new pieces.

**Files:**
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/IntelligenceUpgradeIntegrationTests.swift`

**Step 1: Write the integration test**

```swift
// Tests/SeleneChatTests/Integration/IntelligenceUpgradeIntegrationTests.swift
import XCTest
import SeleneShared

final class IntelligenceUpgradeIntegrationTests: XCTestCase {

    func testFullPromptAssemblyContainsAllSections() {
        // Simulate what ChatViewModel would assemble
        let systemPrompt = """
        You are Selene. Minimal. Precise. Kind.
        RULES:
        - Never summarize unless asked. Engage.
        """

        let contextualBlocks = RetrievedContext(blocks: [
            ContextBlock(type: .emotionalHistory, content: "Felt frustrated about early mornings",
                         sourceDate: Date(), sourceTitle: "Morning frustration"),
            ContextBlock(type: .taskHistory, content: "wake-up-early (abandoned, 12d)"),
            ContextBlock(type: .sentimentTrend, content: "This week (8 notes): frustrated 3x"),
        ])

        let noteContext = "--- Morning Thoughts ---\nContent about morning routines..."

        let fullPrompt = """
        \(systemPrompt)

        ## Context from your history:
        \(contextualBlocks.formatted())

        Notes:
        \(noteContext)

        Question: help me with morning routines
        """

        // Verify all sections present
        XCTAssertTrue(fullPrompt.contains("Selene"))
        XCTAssertTrue(fullPrompt.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(fullPrompt.contains("[TASK HISTORY"))
        XCTAssertTrue(fullPrompt.contains("[EMOTIONAL TREND"))
        XCTAssertTrue(fullPrompt.contains("Morning Thoughts"))
        XCTAssertTrue(fullPrompt.contains("help me with morning routines"))

        // Verify order: system → context → notes → question
        let systemRange = fullPrompt.range(of: "Selene")!
        let contextRange = fullPrompt.range(of: "[EMOTIONAL HISTORY")!
        let notesRange = fullPrompt.range(of: "Morning Thoughts")!
        let questionRange = fullPrompt.range(of: "help me with morning routines")!

        XCTAssertTrue(systemRange.lowerBound < contextRange.lowerBound)
        XCTAssertTrue(contextRange.lowerBound < notesRange.lowerBound)
        XCTAssertTrue(notesRange.lowerBound < questionRange.lowerBound)
    }
}
```

**Step 2: Run test**

Run: `cd SeleneChat && swift test --filter IntelligenceUpgradeIntegrationTests 2>&1 | tail -20`
Expected: PASS (if all prior tasks completed)

**Step 3: Commit**

```bash
git add SeleneChat/Tests/SeleneChatTests/Integration/IntelligenceUpgradeIntegrationTests.swift
git commit -m "test: add full integration test for intelligence upgrade prompt assembly"
```

---

## Task 14: Run Full Test Suite and Fix Any Regressions

**Step 1: Run full test suite**

Run: `cd SeleneChat && swift test 2>&1 | tail -50`

**Step 2: Fix any failures**

The prompt rewrites may break existing tests that assert on old prompt content (e.g., tests checking for "Be conversational and supportive"). Update those tests to match new prompt language.

**Step 3: Verify all pass**

Run: `cd SeleneChat && swift test 2>&1 | grep -E "^Test|passed|failed|error"`
Expected: All tests pass

**Step 4: Commit fixes**

```bash
git commit -m "fix: update existing tests for new prompt language"
```

---

## Task 15: Update Design Doc Status and Documentation

**Files:**
- Modify: `docs/plans/INDEX.md` — move design to "In Progress" or "Done"
- Modify: `.claude/PROJECT-STATUS.md` — add Layer 1+2 completion

**Step 1: Update INDEX.md**

Move `2026-02-24-selene-intelligence-upgrade-design.md` from "Ready" to "Done" with completion date.

**Step 2: Update PROJECT-STATUS.md**

Add to Recent Completions:
```
- **Intelligence Upgrade Layers 1+2** (date) - ContextualRetriever, zen prompt rewrite, expanded planning detection
```

**Step 3: Commit**

```bash
git add docs/plans/INDEX.md .claude/PROJECT-STATUS.md
git commit -m "docs: update status for intelligence upgrade layers 1+2"
```

---

## Summary

| Task | What It Does | Estimated Effort |
|------|-------------|-----------------|
| 1 | Add `essence`/`fidelityTier` to Note model | 15 min |
| 2 | Add `threadDigest`/`emotionalCharge` to Thread model | 15 min |
| 3 | Emotional history query | 30 min |
| 4 | Task outcome query | 30 min |
| 5 | Sentiment trend aggregation | 20 min |
| 6 | ContextualRetriever service | 45 min |
| 7 | Integrate retriever into ChatViewModel | 20 min |
| 8 | Integrate retriever into ThreadWorkspaceChatViewModel | 20 min |
| 9 | Rewrite ChatViewModel system prompts | 30 min |
| 10 | Rewrite ThreadWorkspacePromptBuilder | 30 min |
| 11 | Expand planning intent detection | 15 min |
| 12 | Align DeepDive/Synthesis/Briefing prompts | 30 min |
| 13 | Full integration test | 15 min |
| 14 | Run full suite, fix regressions | 20 min |
| 15 | Update docs and status | 10 min |

**Total: ~15 tasks, ~5-6 hours of focused work**

**Dependencies:** Tasks 1-2 must come first (model fields). Tasks 3-5 must precede Task 6 (queries before retriever). Tasks 6-8 are Layer 1. Tasks 9-12 are Layer 2. Tasks 13-15 are verification.
