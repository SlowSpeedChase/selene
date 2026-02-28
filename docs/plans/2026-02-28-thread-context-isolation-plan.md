# Thread Context Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three bugs found during E2E user testing: thread workspace context leaking across threads, conversation memories contaminating across threads, and new projects defaulting to parked status. Add a golden walkthrough (manual + automated) to prevent regressions.

**Architecture:** Remove global fallback from chunk retrieval, add `thread_id` column to conversation memories with a new migration, and change `createProject()` default status to `active`. All changes are in the SeleneChat Swift package.

**Tech Stack:** Swift 5.9+, SQLite.swift, XCTest

---

### Task 1: Fix Project Status Default

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/ProjectService.swift:178`
- Modify: `SeleneChat/Sources/SeleneChat/Services/ProjectService.swift:198`
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift` (new file)

**Step 1: Create the test file with the first failing test**

Create `SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift`:

```swift
import SeleneShared
import XCTest
import SQLite
@testable import SeleneChat

final class GoldenWalkthroughTests: XCTestCase {

    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_golden_\(UUID().uuidString).db").path

        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath

        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        // Create prerequisite tables not managed by Swift migrations
        try db.run("""
            CREATE TABLE IF NOT EXISTS threads (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                why TEXT,
                summary TEXT,
                status TEXT DEFAULT 'active',
                note_count INTEGER DEFAULT 0,
                momentum_score REAL,
                last_activity_at TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                thread_digest TEXT
            )
        """)

        try db.run("""
            CREATE TABLE IF NOT EXISTS thread_notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                thread_id INTEGER NOT NULL,
                raw_note_id INTEGER NOT NULL,
                added_at TEXT DEFAULT CURRENT_TIMESTAMP,
                relevance_score REAL,
                UNIQUE(thread_id, raw_note_id)
            )
        """)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    // MARK: - Task 1: Project Status

    func testCreateProjectDefaultsToActive() async throws {
        let projectService = ProjectService(db: databaseService.db)
        let project = try await projectService.createProject(name: "Test Project")

        XCTAssertEqual(project.status, .active, "New user-created projects should default to active, not parked")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests/testCreateProjectDefaultsToActive 2>&1 | tail -20`

Expected: FAIL — `XCTAssertEqual failed: ("parked") is not equal to ("active")`

**Step 3: Fix ProjectService.createProject()**

In `SeleneChat/Sources/SeleneChat/Services/ProjectService.swift`:

Change line 178:
```swift
// Before:
projectStatus <- "parked",

// After:
projectStatus <- "active",
```

Change line 198:
```swift
// Before:
status: .parked,

// After:
status: .active,
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests/testCreateProjectDefaultsToActive 2>&1 | tail -10`

Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/ProjectService.swift SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift
git commit -m "fix: new projects default to active status instead of parked"
```

---

### Task 2: Remove Global Fallback from Thread Workspace Chunk Retrieval

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift:284-300`
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift`

**Step 1: Add failing test to GoldenWalkthroughTests**

This test verifies that `ThreadWorkspaceChatViewModel.buildChunkBasedPrompt()` does NOT include content from other threads. Since `buildChunkBasedPrompt` is async and requires Ollama for embeddings, we test the `buildPrompt(for:)` synchronous path and verify the `retrieveChunksForQuery` method stays scoped.

Add to `GoldenWalkthroughTests.swift`:

```swift
    // MARK: - Helpers

    private func insertNote(title: String, content: String, status: String = "processed") throws -> Int64 {
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return -1
        }

        let now = ISO8601DateFormatter().string(from: Date())
        return try db.run("""
            INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, exported_to_obsidian)
            VALUES (?, ?, ?, 'test', ?, ?, ?, ?, ?, 0)
        """, title, content, UUID().uuidString, content.split(separator: " ").count, content.count, now, now, status)
    }

    private func insertThread(name: String, noteCount: Int = 0) throws -> Int64 {
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return -1
        }

        let now = ISO8601DateFormatter().string(from: Date())
        return try db.run("""
            INSERT INTO threads (name, status, note_count, created_at, updated_at)
            VALUES (?, 'active', ?, ?, ?)
        """, name, noteCount, now, now)
    }

    private func assignNoteToThread(noteId: Int64, threadId: Int64) throws {
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        try db.run("""
            INSERT INTO thread_notes (thread_id, raw_note_id)
            VALUES (?, ?)
        """, threadId, noteId)
    }

    // MARK: - Task 2: Thread-Scoped Retrieval

    func testThreadWorkspacePromptOnlyContainsThreadNotes() throws {
        // Set up two threads with distinct notes
        let jtThreadId = try insertThread(name: "Joshua Tree Camping", noteCount: 2)
        let ceramicsThreadId = try insertThread(name: "Ceramics Exploration", noteCount: 2)

        let jtNote1Id = try insertNote(title: "Campsite research", content: "Jumbo Rocks campsite is the most popular in Joshua Tree")
        let jtNote2Id = try insertNote(title: "Hiking plans", content: "Ryan Mountain trail is 3 miles with panoramic desert views")
        let cerNote1Id = try insertNote(title: "Glazing experiments", content: "Tried ash glaze on stoneware, got a beautiful matte finish")
        let cerNote2Id = try insertNote(title: "Studio hours", content: "The ceramics studio is open Tuesday and Thursday evenings")

        try assignNoteToThread(noteId: jtNote1Id, threadId: jtThreadId)
        try assignNoteToThread(noteId: jtNote2Id, threadId: jtThreadId)
        try assignNoteToThread(noteId: cerNote1Id, threadId: ceramicsThreadId)
        try assignNoteToThread(noteId: cerNote2Id, threadId: ceramicsThreadId)

        // Build notes arrays as the app would
        let jtNotes = [
            Note(id: jtNote1Id, title: "Campsite research", content: "Jumbo Rocks campsite is the most popular in Joshua Tree", createdAt: Date()),
            Note(id: jtNote2Id, title: "Hiking plans", content: "Ryan Mountain trail is 3 miles with panoramic desert views", createdAt: Date())
        ]

        let jtThread = Thread(id: jtThreadId, name: "Joshua Tree Camping", status: "active", noteCount: 2)

        // Build prompt for JT thread — should only reference JT content
        let promptBuilder = ThreadWorkspacePromptBuilder()
        let prompt = promptBuilder.buildInitialPrompt(
            thread: jtThread,
            notes: jtNotes,
            tasks: []
        )

        // Verify prompt contains JT content
        XCTAssertTrue(prompt.contains("Joshua Tree"), "Prompt should contain thread name")
        XCTAssertTrue(prompt.contains("Jumbo Rocks") || prompt.contains("Ryan Mountain"), "Prompt should contain thread notes")

        // Verify prompt does NOT contain ceramics content
        XCTAssertFalse(prompt.contains("ceramics"), "Prompt must NOT contain content from other threads")
        XCTAssertFalse(prompt.contains("glazing"), "Prompt must NOT contain content from other threads")
        XCTAssertFalse(prompt.contains("stoneware"), "Prompt must NOT contain content from other threads")
    }
```

**Step 2: Run test to verify it passes (baseline — the prompt builder itself is already scoped)**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests/testThreadWorkspacePromptOnlyContainsThreadNotes 2>&1 | tail -10`

Expected: PASS (the prompt builder is correct; the bug is in the retrieval layer)

**Step 3: Remove the global fallback**

In `SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift`, delete lines 284-300.

Before:
```swift
            let results = chunkRetrievalService.retrieveTopChunks(
                queryEmbedding: queryEmbedding,
                candidates: validCandidates,
                limit: 15,
                minSimilarity: 0.3,
                tokenBudget: 8000
            )

            // If thread-scoped results are poor, try global fallback
            if results.isEmpty || (results.first?.similarity ?? 0) < 0.5 {
                let allCandidates = try await databaseService.getAllChunksWithEmbeddings()
                let validAll: [(chunk: NoteChunk, embedding: [Float])] = allCandidates.compactMap { item in
                    guard let embedding = item.embedding else { return nil }
                    return (chunk: item.chunk, embedding: embedding)
                }
                if !validAll.isEmpty {
                    return chunkRetrievalService.retrieveTopChunks(
                        queryEmbedding: queryEmbedding,
                        candidates: validAll,
                        limit: 15,
                        minSimilarity: 0.3,
                        tokenBudget: 8000
                    )
                }
            }

            return results
```

After:
```swift
            return chunkRetrievalService.retrieveTopChunks(
                queryEmbedding: queryEmbedding,
                candidates: validCandidates,
                limit: 15,
                minSimilarity: 0.3,
                tokenBudget: 8000
            )
```

**Step 4: Run all existing thread workspace tests to verify nothing breaks**

Run: `cd SeleneChat && swift test --filter ThreadWorkspace 2>&1 | tail -20`

Expected: All PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift
git commit -m "fix: remove global fallback from thread workspace chunk retrieval

Thread workspace now stays strictly scoped to thread notes.
Cross-thread context only when user explicitly requests it."
```

---

### Task 3: Add thread_id to Conversation Memories (Schema Migration)

**Files:**
- Create: `SeleneChat/Sources/SeleneChat/Services/Migrations/Migration010_MemoryThreadScope.swift`
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift` (column definition + migration registration + insert/query changes)
- Modify: `SeleneChat/Sources/SeleneShared/Models/ConversationMemory.swift` (add threadId field)
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift`

**Step 1: Add threadId to ConversationMemory model**

In `SeleneChat/Sources/SeleneShared/Models/ConversationMemory.swift`, add a `threadId` property:

```swift
public struct ConversationMemory: Identifiable, Codable, Hashable {
    public let id: Int64
    public let content: String
    public let sourceSessionId: String?
    public let threadId: Int64?          // <-- ADD THIS
    public let memoryType: MemoryType
    public var confidence: Double
    public var lastAccessed: Date?
    public let createdAt: Date
    public var updatedAt: Date
```

Update the `init` to include `threadId`:

```swift
    public init(
        id: Int64,
        content: String,
        sourceSessionId: String? = nil,
        threadId: Int64? = nil,           // <-- ADD THIS
        memoryType: MemoryType,
        confidence: Double = 1.0,
        lastAccessed: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.sourceSessionId = sourceSessionId
        self.threadId = threadId           // <-- ADD THIS
        self.memoryType = memoryType
        self.confidence = confidence
        self.lastAccessed = lastAccessed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
```

**Step 2: Create migration file**

Create `SeleneChat/Sources/SeleneChat/Services/Migrations/Migration010_MemoryThreadScope.swift`:

```swift
import SQLite

enum Migration010_MemoryThreadScope {
    static func run(db: Connection) throws {
        // Add thread_id column to conversation_memories
        // Nullable — general chat memories stay null, thread workspace memories get tagged
        do {
            try db.run("ALTER TABLE conversation_memories ADD COLUMN thread_id INTEGER REFERENCES threads(id)")
        } catch {
            // Column may already exist
        }

        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_thread ON conversation_memories(thread_id)")

        print("Migration 010: Added thread_id to conversation_memories")
    }
}
```

**Step 3: Register migration in DatabaseService**

Find the migration runner in `DatabaseService.swift` (search for `Migration009`). Add after it:

```swift
try Migration010_MemoryThreadScope.run(db: db)
```

**Step 4: Add column expression to DatabaseService**

In `DatabaseService.swift` near line 145, after the existing memory column definitions, add:

```swift
private let memThreadId = Expression<Int64?>("thread_id")
```

**Step 5: Update insertMemory to accept threadId**

In `DatabaseService.swift`, update the `insertMemory` function signature (line ~1935):

```swift
func insertMemory(content: String, type: ConversationMemory.MemoryType, confidence: Double, sourceSessionId: UUID?, threadId: Int64? = nil, embedding: [Float]? = nil) async throws -> Int64 {
```

Add after the session ID setter block (around line 1953):

```swift
if let threadId = threadId {
    setter.append(memThreadId <- threadId)
}
```

**Step 6: Add a test for thread-scoped memory insertion**

Add to `GoldenWalkthroughTests.swift`:

```swift
    // MARK: - Task 3: Thread-Scoped Memories

    func testInsertMemoryWithThreadId() async throws {
        let threadId = try insertThread(name: "Test Thread")

        let memoryId = try await databaseService.insertMemory(
            content: "User prefers morning hikes",
            type: .fact,
            confidence: 0.9,
            sourceSessionId: nil,
            threadId: threadId
        )

        XCTAssertGreaterThan(memoryId, 0)

        // Verify thread_id was stored
        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        let memoriesTable = Table("conversation_memories")
        let memIdCol = Expression<Int64>("id")
        let threadIdCol = Expression<Int64?>("thread_id")

        let row = try db.pluck(memoriesTable.filter(memIdCol == memoryId))
        let storedThreadId = try row?.get(threadIdCol)

        XCTAssertEqual(storedThreadId, threadId, "Memory should be tagged with thread_id")
    }

    func testInsertMemoryWithoutThreadIdIsNull() async throws {
        let memoryId = try await databaseService.insertMemory(
            content: "User likes coffee",
            type: .preference,
            confidence: 0.8,
            sourceSessionId: nil
        )

        guard let db = databaseService.db else {
            XCTFail("Database not connected")
            return
        }

        let memoriesTable = Table("conversation_memories")
        let memIdCol = Expression<Int64>("id")
        let threadIdCol = Expression<Int64?>("thread_id")

        let row = try db.pluck(memoriesTable.filter(memIdCol == memoryId))
        let storedThreadId = try row?.get(threadIdCol)

        XCTAssertNil(storedThreadId, "General chat memories should have null thread_id")
    }
```

**Step 7: Run tests**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests 2>&1 | tail -20`

Expected: All PASS

**Step 8: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Models/ConversationMemory.swift \
  SeleneChat/Sources/SeleneChat/Services/Migrations/Migration010_MemoryThreadScope.swift \
  SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift \
  SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift
git commit -m "feat: add thread_id to conversation_memories for thread-scoped memory

New migration adds nullable thread_id column. General chat memories
stay null (available everywhere). Thread workspace memories get tagged."
```

---

### Task 4: Thread-Scope Memory Consolidation and Retrieval

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/MemoryService.swift:112,341`
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift` (add filtered query methods)
- Modify: `SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift:927`
- Modify: `SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift` (pass threadId)
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift`

**Step 1: Add failing test for thread-filtered memory retrieval**

Add to `GoldenWalkthroughTests.swift`:

```swift
    func testMemoryRetrievalFiltersByThread() async throws {
        let jtThreadId = try insertThread(name: "Joshua Tree")
        let cerThreadId = try insertThread(name: "Ceramics")

        // Insert memories with different thread scopes
        _ = try await databaseService.insertMemory(
            content: "User needs camping packing list",
            type: .fact, confidence: 0.9, sourceSessionId: nil, threadId: jtThreadId
        )
        _ = try await databaseService.insertMemory(
            content: "User has a ceramics studio",
            type: .fact, confidence: 0.9, sourceSessionId: nil, threadId: cerThreadId
        )
        _ = try await databaseService.insertMemory(
            content: "User prefers bullet-point responses",
            type: .preference, confidence: 0.9, sourceSessionId: nil, threadId: nil
        )

        // Retrieve for JT thread — should get JT + global, not ceramics
        let jtMemories = try await databaseService.getMemoriesForThread(threadId: jtThreadId, limit: 10)

        let contents = jtMemories.map { $0.content }
        XCTAssertTrue(contents.contains("User needs camping packing list"), "Should include thread-specific memory")
        XCTAssertTrue(contents.contains("User prefers bullet-point responses"), "Should include global memory")
        XCTAssertFalse(contents.contains("User has a ceramics studio"), "Must NOT include other thread's memory")
    }
```

**Step 2: Run to verify it fails**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests/testMemoryRetrievalFiltersByThread 2>&1 | tail -10`

Expected: FAIL — `getMemoriesForThread` does not exist yet

**Step 3: Add getMemoriesForThread to DatabaseService**

In `DatabaseService.swift`, after the existing `getAllMemories` method, add:

```swift
    /// Get memories scoped to a specific thread (plus global memories with null thread_id)
    func getMemoriesForThread(threadId: Int64, limit: Int = 50) async throws -> [ConversationMemory] {
        guard let db = db else {
            throw DatabaseError.notConnected
        }

        let query = memoriesTable
            .filter(memThreadId == threadId || memThreadId == nil)
            .order(memUpdatedAt.desc)
            .limit(limit)

        return try db.prepare(query).map { row in
            ConversationMemory(
                id: try row.get(memId),
                content: try row.get(memContent),
                sourceSessionId: try row.get(memSourceSessionId),
                threadId: try row.get(memThreadId),
                memoryType: ConversationMemory.MemoryType(rawValue: try row.get(memType) ?? "fact") ?? .fact,
                confidence: try row.get(memConfidence),
                lastAccessed: (try? row.get(memLastAccessed)).flatMap { self.parseDateString($0) },
                createdAt: self.parseDateString(try row.get(memCreatedAt)) ?? Date(),
                updatedAt: self.parseDateString(try row.get(memUpdatedAt)) ?? Date()
            )
        }
    }
```

Also update existing memory parsing calls elsewhere in DatabaseService to populate `threadId` in any `ConversationMemory` constructors (search for `ConversationMemory(` and add `threadId: try row.get(memThreadId)` where applicable).

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests/testMemoryRetrievalFiltersByThread 2>&1 | tail -10`

Expected: PASS

**Step 5: Update MemoryService.consolidateMemory to accept threadId**

In `MemoryService.swift`, update `consolidateMemory` signature (line ~112):

```swift
func consolidateMemory(
    candidateFact: CandidateFact,
    sessionId: UUID,
    threadId: Int64? = nil    // <-- ADD THIS
) async throws {
```

Pass `threadId` through to `databaseService.insertMemory` in the ADD branch (line ~148):

```swift
_ = try await databaseService.insertMemory(
    content: candidateFact.fact,
    type: memoryType,
    confidence: candidateFact.confidence,
    sourceSessionId: sessionId,
    threadId: threadId,        // <-- ADD THIS
    embedding: factEmbedding
)
```

**Step 6: Update MemoryService.getRelevantMemories to accept optional threadId**

In `MemoryService.swift`, update `getRelevantMemories` signature (line ~341):

```swift
func getRelevantMemories(for query: String, limit: Int = 5, threadId: Int64? = nil) async throws -> [ConversationMemory] {
```

When `threadId` is provided, filter results to only include memories from that thread or global:

```swift
    // Try embedding-based retrieval
    do {
        let queryEmbedding = try await ollamaService.embed(text: query)

        // If thread-scoped, only search thread + global memories
        let allMemories: [(memory: ConversationMemory, embedding: [Float])]
        if let threadId = threadId {
            let threadMemories = try await databaseService.getMemoriesForThread(threadId: threadId, limit: 50)
            let withEmbeddings = try await databaseService.getMemoriesWithEmbeddings(ids: threadMemories.map { $0.id })
            allMemories = withEmbeddings
        } else {
            allMemories = try await databaseService.getAllMemoriesWithEmbeddings()
        }
```

Note: `getMemoriesWithEmbeddings(ids:)` may need to be added to DatabaseService if not already present. If it doesn't exist, an alternative is to filter `getAllMemoriesWithEmbeddings()` to only include memories whose `threadId` matches or is nil.

**Step 7: Update ChatViewModel.extractMemoriesFromExchange**

In `ChatViewModel.swift` at line ~944, pass `threadId: nil` (general chat has no thread):

```swift
try await memoryService.consolidateMemory(
    candidateFact: fact,
    sessionId: currentSession.id,
    threadId: nil
)
```

**Step 8: Update ThreadWorkspaceChatViewModel to pass threadId**

The thread workspace chat currently doesn't extract memories (it uses the simpler `sendMessage` flow). If memory extraction is added in the future, it should pass `thread.id`. For now, verify the workspace chat's `buildContextualSection` already scopes by threadId (it does — line 350-353 passes `threadId: thread.id`).

**Step 9: Run all tests**

Run: `cd SeleneChat && swift test 2>&1 | tail -20`

Expected: All tests PASS. Fix any compilation errors from the signature changes (callers of `consolidateMemory` and `getRelevantMemories` that don't pass the new optional parameter will use defaults).

**Step 10: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/MemoryService.swift \
  SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift \
  SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift \
  SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift \
  SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift
git commit -m "feat: thread-scope memory consolidation and retrieval

Memory extraction now tags memories with thread_id when from thread
workspace. Retrieval filters to thread + global memories. Prevents
cross-thread contamination of hallucinated facts."
```

---

### Task 5: Write Manual Golden Walkthrough Script

**Files:**
- Create: `docs/plans/golden-walkthrough.md`

**Step 1: Create the manual walkthrough**

Create `docs/plans/golden-walkthrough.md`:

```markdown
# Golden Walkthrough — Manual Test Script

**Purpose:** End-to-end verification of SeleneChat core features against the dev database. Run after significant changes to catch UX regressions.

## Prerequisites

1. Dev SeleneChat running from CLI: `cd SeleneChat && .build/debug/SeleneChat`
2. Clean state:
   ```bash
   sqlite3 ~/selene-data-dev/selene.db "DELETE FROM conversation_memories;"
   sqlite3 ~/selene-data-dev/selene.db "DELETE FROM projects WHERE is_system IS NULL OR is_system = 0;"
   sqlite3 ~/selene-data-dev/selene.db "DELETE FROM chat_sessions;"
   ```

## Walkthrough

### 1. Planning — Project Creation

| Step | Do | Expect |
|------|----|--------|
| 1.1 | Click Planning tab | Active Projects section visible, empty (no user projects) |
| 1.2 | Open Inbox | Notes from dev database appear |
| 1.3 | Create project from first note | Project immediately appears in Active Projects list |
| 1.4 | Verify in DB | `sqlite3 ~/selene-data-dev/selene.db "SELECT name, status FROM projects WHERE is_system IS NULL OR is_system = 0;"` → status = `active` |

### 2. Thread Workspace — Joshua Tree (Context Isolation)

| Step | Do | Expect |
|------|----|--------|
| 2.1 | Click Threads tab | 14 threads visible |
| 2.2 | Click "Joshua Tree Camping Trip" | Thread workspace opens with summary and notes |
| 2.3 | Type: "help me make a packing list" | Response references camping gear, hiking, weather |
| 2.4 | **CHECK:** Does response mention ceramics, studio, glazing? | **NO.** If it does, the global fallback fix failed |
| 2.5 | Verify memories | `sqlite3 ~/selene-data-dev/selene.db "SELECT content, thread_id FROM conversation_memories;"` → all memories have thread_id = Joshua Tree's ID |

### 3. Thread Workspace — Ceramics (Cross-Thread Isolation)

| Step | Do | Expect |
|------|----|--------|
| 3.1 | Navigate back to Threads | Thread list visible |
| 3.2 | Click "Ceramics Exploration" | Fresh workspace, no Joshua Tree context |
| 3.3 | Type: "what should I work on next?" | Response references glazing, techniques, studio hours |
| 3.4 | **CHECK:** Does response mention camping, Joshua Tree, packing? | **NO.** If it does, memory contamination fix failed |
| 3.5 | Verify memories | `sqlite3 ~/selene-data-dev/selene.db "SELECT content, thread_id FROM conversation_memories;"` → no cross-thread contamination |

### 4. General Chat (Global Memories Still Work)

| Step | Do | Expect |
|------|----|--------|
| 4.1 | Click Chat tab | General chat interface |
| 4.2 | Type: "what have I been working on?" | Response references multiple threads (synthesis mode) |
| 4.3 | Verify it uses global context | Response mentions Joshua Tree AND Ceramics (appropriate in general chat) |

## Pass Criteria

All steps complete with no unexpected cross-thread content. Thread workspaces stay scoped. General chat remains global.
```

**Step 2: Commit**

```bash
git add docs/plans/golden-walkthrough.md
git commit -m "docs: add manual golden walkthrough test script"
```

---

### Task 6: Run Full Test Suite and Final Verification

**Files:** None (verification only)

**Step 1: Run complete test suite**

Run: `cd SeleneChat && swift test 2>&1 | tail -30`

Expected: All tests PASS, including new GoldenWalkthroughTests

**Step 2: Run golden walkthrough tests specifically**

Run: `cd SeleneChat && swift test --filter GoldenWalkthroughTests 2>&1 | tail -20`

Expected: All 4 tests PASS:
- `testCreateProjectDefaultsToActive`
- `testThreadWorkspacePromptOnlyContainsThreadNotes`
- `testInsertMemoryWithThreadId`
- `testInsertMemoryWithoutThreadIdIsNull`
- `testMemoryRetrievalFiltersByThread`

**Step 3: Rebuild and relaunch dev SeleneChat**

```bash
cd SeleneChat && swift build && .build/debug/SeleneChat &
```

**Step 4: Run the manual golden walkthrough**

Follow `docs/plans/golden-walkthrough.md` step by step.

**Step 5: Final commit if any fixes were needed**

```bash
git add -A && git commit -m "fix: address issues found during golden walkthrough verification"
```
