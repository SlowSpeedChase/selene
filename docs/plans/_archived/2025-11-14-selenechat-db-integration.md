# SeleneChat Database Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add chat session persistence to Selene database with 30-day compression via Apple Intelligence

**Architecture:** Extend existing DatabaseService with chat CRUD operations. Add CompressionService for background summarization. Enhance ChatSession model with persistence fields. Hook ChatViewModel to save on session switch.

**Tech Stack:** Swift 5.9, SQLite.swift, NaturalLanguage framework, SwiftUI

**Design Reference:** `docs/plans/2025-11-14-selenechat-database-integration-design.md`

---

## Prerequisites

**Current location:** `/Users/chaseeasterling/selene/.worktrees/selenechat-db-integration/SeleneChat`

**Verify setup:**
```bash
pwd  # Should show .worktrees/selenechat-db-integration/SeleneChat
git branch  # Should show feature/selenechat-db-integration
swift build  # Should succeed
```

---

## Phase 1: Fix Test Infrastructure

**Before writing tests, fix Package.swift to support proper testing**

### Task 1.1: Fix Package.swift Test Target

**Files:**
- Modify: `Package.swift:26-30`

**Step 1: Update test target configuration**

Edit `Package.swift`:

```swift
// Replace this:
.executableTarget(
    name: "SeleneChatTests",
    dependencies: [],
    path: "Tests/SeleneChatTests"
)

// With this:
.testTarget(
    name: "SeleneChatTests",
    dependencies: ["SeleneChat"],
    path: "Tests/SeleneChatTests"
)
```

**Step 2: Verify tests can run**

Run: `swift test`
Expected: Tests now recognized (may still fail or pass, but no "no tests found" error)

**Step 3: Commit**

```bash
git add Package.swift
git commit -m "fix: convert SeleneChatTests to proper test target

Enables swift test command to recognize and run tests.
"
```

---

## Phase 2: Database Migration

### Task 2.1: Create Migration SQL File

**Files:**
- Create: `../../database/migrations/005_add_chat_sessions.sql`

**Step 1: Create migration file**

Create file with exact SQL:

```sql
-- Migration: Add chat session storage
-- Date: 2025-11-14
-- Description: Enable SeleneChat to persist conversations with 30-day retention

CREATE TABLE IF NOT EXISTS chat_sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    message_count INTEGER NOT NULL,

    -- Retention and compression
    is_pinned INTEGER DEFAULT 0,
    compression_state TEXT DEFAULT 'full',
    compressed_at TEXT,

    -- Content (mutually exclusive based on compression_state)
    full_messages_json TEXT,
    summary_text TEXT
);

CREATE INDEX idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
CREATE INDEX idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);
```

**Step 2: Verify SQL syntax**

Run from project root:
```bash
cd ../.. && sqlite3 :memory: < database/migrations/005_add_chat_sessions.sql && echo "✅ SQL valid"
```

Expected: "✅ SQL valid"

**Step 3: Commit**

```bash
git add database/migrations/005_add_chat_sessions.sql
git commit -m "feat: add chat_sessions table migration

Stores chat history with 30-day retention policy.
Fields: id, title, timestamps, compression state, content.
"
```

---

## Phase 3: Enhance ChatSession Model

### Task 3.1: Add Persistence Fields to ChatSession

**Files:**
- Modify: `Sources/Models/ChatSession.swift`

**Step 1: Add compression state enum**

Add after existing code:

```swift
extension ChatSession {
    enum CompressionState: String, Codable {
        case full          // Full messages available
        case processing    // Compression in progress
        case compressed    // Only summary available
    }
}
```

**Step 2: Add persistence fields to ChatSession struct**

Add new properties to ChatSession:

```swift
struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date

    // NEW: Persistence tracking
    var isPinned: Bool = false
    var compressionState: CompressionState = .full
    var compressedAt: Date?
    var summaryText: String?

    // ... rest of existing code
}
```

**Step 3: Verify build**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/Models/ChatSession.swift
git commit -m "feat: add persistence fields to ChatSession

Fields: isPinned, compressionState, compressedAt, summaryText.
Supports 30-day compression workflow.
"
```

---

## Phase 4: Database Service - Save Session (TDD)

### Task 4.1: Write Failing Test for saveSession

**Files:**
- Create: `Tests/SeleneChatTests/DatabaseServiceTests.swift`

**Step 1: Create test file with setup**

Create new file:

```swift
import XCTest
@testable import SeleneChat

final class DatabaseServiceTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDBPath: String!

    override func setUp() async throws {
        // Use in-memory database for tests
        testDBPath = ":memory:"
        databaseService = DatabaseService(dbPath: testDBPath)

        // Run migration
        try await databaseService.runMigrations()
    }

    override func tearDown() async throws {
        databaseService = nil
    }

    func testSaveAndLoadSession() async throws {
        // Arrange
        let session = ChatSession(
            id: UUID(),
            title: "Test Session",
            messages: [
                Message(id: UUID(), role: .user, content: "Hello", timestamp: Date())
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        try await databaseService.saveSession(session)
        let loaded = try await databaseService.loadSessions()

        // Assert
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, session.id)
        XCTAssertEqual(loaded[0].title, session.title)
        XCTAssertEqual(loaded[0].messages.count, 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testSaveAndLoadSession`
Expected: FAIL - "Value of type 'DatabaseService' has no member 'saveSession'"

**Step 3: Commit failing test**

```bash
git add Tests/SeleneChatTests/DatabaseServiceTests.swift
git commit -m "test: add failing test for chat session persistence

RED: saveSession and loadSessions methods don't exist yet.
"
```

### Task 4.2: Add DatabaseService Initializer Support

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Update DatabaseService to support custom path**

Find the DatabaseService initialization code and update to accept optional path:

```swift
@MainActor
class DatabaseService: ObservableObject {
    @Published var isConnected = false
    private var db: Connection?
    private let dbPath: String

    init(dbPath: String = "/selene/data/selene.db") {
        self.dbPath = dbPath
        connect()
    }

    private func connect() {
        do {
            db = try Connection(dbPath)
            isConnected = true
        } catch {
            print("Database connection failed: \(error)")
            isConnected = false
        }
    }

    // ... rest of existing code
}
```

**Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "refactor: add dbPath parameter to DatabaseService

Enables test doubles with in-memory database.
"
```

### Task 4.3: Add runMigrations Method

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Add migration method**

Add method to DatabaseService:

```swift
func runMigrations() async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    // Read and execute migration
    let migrationSQL = """
    CREATE TABLE IF NOT EXISTS chat_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        message_count INTEGER NOT NULL,
        is_pinned INTEGER DEFAULT 0,
        compression_state TEXT DEFAULT 'full',
        compressed_at TEXT,
        full_messages_json TEXT,
        summary_text TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);
    """

    try db.execute(migrationSQL)
}

enum DatabaseError: Error {
    case notConnected
    case serializationFailed
    case sessionNotFound
}
```

**Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "feat: add runMigrations method for chat_sessions table

Creates table and indexes for session persistence.
"
```

### Task 4.4: Implement saveSession (Make Test Pass)

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Import Foundation for JSON encoding**

Add at top of file if not present:

```swift
import Foundation
import SQLite
```

**Step 2: Add saveSession method**

Add to DatabaseService:

```swift
func saveSession(_ session: ChatSession) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    // Serialize messages to JSON
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let messagesData = try encoder.encode(session.messages)
    guard let messagesJSON = String(data: messagesData, encoding: .utf8) else {
        throw DatabaseError.serializationFailed
    }

    // ISO8601 formatter for dates
    let dateFormatter = ISO8601DateFormatter()

    let insert = """
    INSERT OR REPLACE INTO chat_sessions (
        id, title, created_at, updated_at, message_count,
        is_pinned, compression_state, compressed_at,
        full_messages_json, summary_text
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    try db.run(insert,
        session.id.uuidString,
        session.title,
        dateFormatter.string(from: session.createdAt),
        dateFormatter.string(from: session.updatedAt),
        session.messages.count,
        session.isPinned ? 1 : 0,
        session.compressionState.rawValue,
        session.compressedAt.map { dateFormatter.string(from: $0) },
        session.compressionState == .full ? messagesJSON : nil,
        session.summaryText
    )
}
```

**Step 3: Add loadSessions method**

Add to DatabaseService:

```swift
func loadSessions() async throws -> [ChatSession] {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let query = "SELECT * FROM chat_sessions ORDER BY updated_at DESC"
    var sessions: [ChatSession] = []

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let dateFormatter = ISO8601DateFormatter()

    for row in try db.prepare(query) {
        let id = UUID(uuidString: row[0] as! String)!
        let title = row[1] as! String
        let createdAt = dateFormatter.date(from: row[2] as! String)!
        let updatedAt = dateFormatter.date(from: row[3] as! String)!
        let isPinned = (row[5] as! Int64) == 1
        let compressionState = ChatSession.CompressionState(rawValue: row[6] as! String)!
        let compressedAt = (row[7] as? String).flatMap { dateFormatter.date(from: $0) }
        let messagesJSON = row[8] as? String
        let summaryText = row[9] as? String

        var messages: [Message] = []
        if let json = messagesJSON, let data = json.data(using: .utf8) {
            messages = try decoder.decode([Message].self, from: data)
        }

        let session = ChatSession(
            id: id,
            title: title,
            messages: messages,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: isPinned,
            compressionState: compressionState,
            compressedAt: compressedAt,
            summaryText: summaryText
        )

        sessions.append(session)
    }

    return sessions
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter testSaveAndLoadSession`
Expected: GREEN - Test passes

**Step 5: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "feat: implement saveSession and loadSessions

GREEN: Chat sessions now persist to SQLite.
Serializes messages as JSON, handles all fields.
"
```

---

## Phase 5: Database Service - Delete Session (TDD)

### Task 5.1: Write Failing Test for deleteSession

**Files:**
- Modify: `Tests/SeleneChatTests/DatabaseServiceTests.swift`

**Step 1: Add test**

Add to DatabaseServiceTests class:

```swift
func testDeleteSession() async throws {
    // Arrange
    let session = ChatSession(
        id: UUID(),
        title: "To Delete",
        messages: [],
        createdAt: Date(),
        updatedAt: Date()
    )
    try await databaseService.saveSession(session)

    // Act
    try await databaseService.deleteSession(session)
    let loaded = try await databaseService.loadSessions()

    // Assert
    XCTAssertEqual(loaded.count, 0)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testDeleteSession`
Expected: FAIL - "Value of type 'DatabaseService' has no member 'deleteSession'"

**Step 3: Commit failing test**

```bash
git add Tests/SeleneChatTests/DatabaseServiceTests.swift
git commit -m "test: add failing test for deleteSession

RED: deleteSession method doesn't exist yet.
"
```

### Task 5.2: Implement deleteSession

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Add method**

Add to DatabaseService:

```swift
func deleteSession(_ session: ChatSession) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let delete = "DELETE FROM chat_sessions WHERE id = ?"
    try db.run(delete, session.id.uuidString)
}
```

**Step 2: Run test to verify it passes**

Run: `swift test --filter testDeleteSession`
Expected: GREEN

**Step 3: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "feat: implement deleteSession

GREEN: Sessions can now be deleted from database.
"
```

---

## Phase 6: Database Service - Pin Management (TDD)

### Task 6.1: Write Failing Test for updateSessionPin

**Files:**
- Modify: `Tests/SeleneChatTests/DatabaseServiceTests.swift`

**Step 1: Add test**

Add to DatabaseServiceTests:

```swift
func testUpdateSessionPin() async throws {
    // Arrange
    let session = ChatSession(
        id: UUID(),
        title: "Pin Test",
        messages: [],
        createdAt: Date(),
        updatedAt: Date()
    )
    try await databaseService.saveSession(session)

    // Act
    try await databaseService.updateSessionPin(sessionId: session.id, isPinned: true)
    let loaded = try await databaseService.loadSessions()

    // Assert
    XCTAssertEqual(loaded[0].isPinned, true)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testUpdateSessionPin`
Expected: FAIL

**Step 3: Commit**

```bash
git add Tests/SeleneChatTests/DatabaseServiceTests.swift
git commit -m "test: add failing test for updateSessionPin

RED: Pin update method doesn't exist yet.
"
```

### Task 6.2: Implement updateSessionPin

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Add method**

Add to DatabaseService:

```swift
func updateSessionPin(sessionId: UUID, isPinned: Bool) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let update = "UPDATE chat_sessions SET is_pinned = ? WHERE id = ?"
    try db.run(update, isPinned ? 1 : 0, sessionId.uuidString)
}
```

**Step 2: Run test to verify it passes**

Run: `swift test --filter testUpdateSessionPin`
Expected: GREEN

**Step 3: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "feat: implement updateSessionPin

GREEN: Sessions can be pinned/unpinned.
"
```

---

## Phase 7: Database Service - Compression Queries (TDD)

### Task 7.1: Write Failing Test for getSessionsReadyForCompression

**Files:**
- Modify: `Tests/SeleneChatTests/DatabaseServiceTests.swift`

**Step 1: Add test**

Add to DatabaseServiceTests:

```swift
func testGetSessionsReadyForCompression() async throws {
    // Arrange - Create old session (31 days ago)
    let oldDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
    let oldSession = ChatSession(
        id: UUID(),
        title: "Old Session",
        messages: [],
        createdAt: oldDate,
        updatedAt: oldDate
    )

    // Create recent session
    let recentSession = ChatSession(
        id: UUID(),
        title: "Recent Session",
        messages: [],
        createdAt: Date(),
        updatedAt: Date()
    )

    // Create old pinned session
    var pinnedSession = ChatSession(
        id: UUID(),
        title: "Pinned Old",
        messages: [],
        createdAt: oldDate,
        updatedAt: oldDate
    )
    pinnedSession.isPinned = true

    try await databaseService.saveSession(oldSession)
    try await databaseService.saveSession(recentSession)
    try await databaseService.saveSession(pinnedSession)

    // Act
    let ready = try await databaseService.getSessionsReadyForCompression()

    // Assert
    XCTAssertEqual(ready.count, 1)
    XCTAssertEqual(ready[0].id, oldSession.id)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testGetSessionsReadyForCompression`
Expected: FAIL

**Step 3: Commit**

```bash
git add Tests/SeleneChatTests/DatabaseServiceTests.swift
git commit -m "test: add failing test for compression query

RED: Checks 30-day threshold and excludes pinned sessions.
"
```

### Task 7.2: Implement getSessionsReadyForCompression

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Add method**

Add to DatabaseService:

```swift
func getSessionsReadyForCompression() async throws -> [ChatSession] {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    // Get sessions older than 30 days, not pinned, in full state
    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    let dateFormatter = ISO8601DateFormatter()
    let cutoffDate = dateFormatter.string(from: thirtyDaysAgo)

    let query = """
    SELECT * FROM chat_sessions
    WHERE created_at < ?
    AND is_pinned = 0
    AND compression_state = 'full'
    ORDER BY created_at ASC
    """

    var sessions: [ChatSession] = []
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for row in try db.prepare(query, cutoffDate) {
        let id = UUID(uuidString: row[0] as! String)!
        let title = row[1] as! String
        let createdAt = dateFormatter.date(from: row[2] as! String)!
        let updatedAt = dateFormatter.date(from: row[3] as! String)!
        let messagesJSON = row[8] as? String

        var messages: [Message] = []
        if let json = messagesJSON, let data = json.data(using: .utf8) {
            messages = try decoder.decode([Message].self, from: data)
        }

        let session = ChatSession(
            id: id,
            title: title,
            messages: messages,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        sessions.append(session)
    }

    return sessions
}
```

**Step 2: Run test to verify it passes**

Run: `swift test --filter testGetSessionsReadyForCompression`
Expected: GREEN

**Step 3: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "feat: implement getSessionsReadyForCompression

GREEN: Finds sessions older than 30 days for compression.
Excludes pinned and already-compressed sessions.
"
```

---

## Phase 8: Database Service - Compression Execution (TDD)

### Task 8.1: Write Failing Test for compressSession

**Files:**
- Modify: `Tests/SeleneChatTests/DatabaseServiceTests.swift`

**Step 1: Add test**

Add to DatabaseServiceTests:

```swift
func testCompressSession() async throws {
    // Arrange
    let session = ChatSession(
        id: UUID(),
        title: "To Compress",
        messages: [
            Message(id: UUID(), role: .user, content: "Query 1", timestamp: Date()),
            Message(id: UUID(), role: .assistant, content: "Answer 1", timestamp: Date())
        ],
        createdAt: Date(),
        updatedAt: Date()
    )
    try await databaseService.saveSession(session)

    let summary = "Summary: User asked about feature X"

    // Act
    try await databaseService.compressSession(sessionId: session.id, summary: summary)
    let loaded = try await databaseService.loadSessions()

    // Assert
    XCTAssertEqual(loaded[0].compressionState, .compressed)
    XCTAssertEqual(loaded[0].summaryText, summary)
    XCTAssertEqual(loaded[0].messages.count, 0) // Full messages cleared
    XCTAssertNotNil(loaded[0].compressedAt)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testCompressSession`
Expected: FAIL

**Step 3: Commit**

```bash
git add Tests/SeleneChatTests/DatabaseServiceTests.swift
git commit -m "test: add failing test for compressSession

RED: Verifies state transition and summary storage.
"
```

### Task 8.2: Implement compressSession

**Files:**
- Modify: `Sources/Services/DatabaseService.swift`

**Step 1: Add method**

Add to DatabaseService:

```swift
func compressSession(sessionId: UUID, summary: String) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let dateFormatter = ISO8601DateFormatter()
    let now = dateFormatter.string(from: Date())

    let update = """
    UPDATE chat_sessions
    SET compression_state = 'compressed',
        compressed_at = ?,
        full_messages_json = NULL,
        summary_text = ?
    WHERE id = ?
    """

    try db.run(update, now, summary, sessionId.uuidString)
}
```

**Step 2: Add updateCompressionState helper**

Add to DatabaseService:

```swift
func updateCompressionState(sessionId: UUID, state: ChatSession.CompressionState) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let update = "UPDATE chat_sessions SET compression_state = ? WHERE id = ?"
    try db.run(update, state.rawValue, sessionId.uuidString)
}
```

**Step 3: Run test to verify it passes**

Run: `swift test --filter testCompressSession`
Expected: GREEN

**Step 4: Commit**

```bash
git add Sources/Services/DatabaseService.swift
git commit -m "feat: implement compressSession

GREEN: Transitions session to compressed state.
Clears full messages, stores summary, sets timestamp.
"
```

---

## Phase 9: CompressionService (TDD)

### Task 9.1: Create CompressionService with Test

**Files:**
- Create: `Sources/Services/CompressionService.swift`
- Create: `Tests/SeleneChatTests/CompressionServiceTests.swift`

**Step 1: Write failing test**

Create test file:

```swift
import XCTest
@testable import SeleneChat

final class CompressionServiceTests: XCTestCase {
    var compressionService: CompressionService!
    var databaseService: DatabaseService!

    override func setUp() async throws {
        databaseService = DatabaseService(dbPath: ":memory:")
        try await databaseService.runMigrations()
        compressionService = CompressionService(databaseService: databaseService)
    }

    func testGenerateSummaryExtractsUserQueries() async throws {
        // Arrange
        let session = ChatSession(
            id: UUID(),
            title: "Test Session",
            messages: [
                Message(id: UUID(), role: .user, content: "What is the weather?", timestamp: Date()),
                Message(id: UUID(), role: .assistant, content: "It's sunny", timestamp: Date()),
                Message(id: UUID(), role: .user, content: "Tell me about Swift", timestamp: Date())
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let summary = await compressionService.generateSummary(for: session)

        // Assert
        XCTAssertTrue(summary.contains("Test Session"))
        XCTAssertTrue(summary.contains("What is the weather?"))
        XCTAssertTrue(summary.contains("Tell me about Swift"))
        XCTAssertTrue(summary.contains("Questions asked: 2"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testGenerateSummaryExtractsUserQueries`
Expected: FAIL - "No such module 'CompressionService'"

**Step 3: Commit failing test**

```bash
git add Tests/SeleneChatTests/CompressionServiceTests.swift
git commit -m "test: add failing test for CompressionService

RED: Summary generation not implemented yet.
"
```

### Task 9.2: Implement CompressionService

**Files:**
- Create: `Sources/Services/CompressionService.swift`

**Step 1: Create service**

Create file:

```swift
import Foundation

@MainActor
class CompressionService: ObservableObject {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    func checkAndCompressSessions() async {
        guard let sessions = try? await databaseService.getSessionsReadyForCompression() else {
            return
        }

        for session in sessions {
            await compressSession(session)
        }
    }

    private func compressSession(_ session: ChatSession) async {
        // Mark as processing
        try? await databaseService.updateCompressionState(
            sessionId: session.id,
            state: .processing
        )

        // Generate summary
        let summary = await generateSummary(for: session)

        // Save compressed version
        try? await databaseService.compressSession(
            sessionId: session.id,
            summary: summary
        )
    }

    func generateSummary(for session: ChatSession) async -> String {
        let userQueries = session.messages
            .filter { $0.role == .user }
            .map { $0.content }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let summary = """
        Session: \(session.title)
        Date: \(dateFormatter.string(from: session.createdAt))
        Questions asked: \(userQueries.count)

        Key queries:
        \(userQueries.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
        """

        return summary
    }
}
```

**Step 2: Run test to verify it passes**

Run: `swift test --filter testGenerateSummaryExtractsUserQueries`
Expected: GREEN

**Step 3: Commit**

```bash
git add Sources/Services/CompressionService.swift
git commit -m "feat: implement CompressionService

GREEN: Generates summaries from user queries.
Handles compression workflow with state transitions.
"
```

---

## Phase 10: ChatViewModel Integration (TDD)

### Task 10.1: Write Failing Test for Session Persistence

**Files:**
- Create: `Tests/SeleneChatTests/ChatViewModelTests.swift`

**Step 1: Write test**

Create file:

```swift
import XCTest
@testable import SeleneChat

final class ChatViewModelTests: XCTestCase {
    var viewModel: ChatViewModel!
    var databaseService: DatabaseService!

    override func setUp() async throws {
        databaseService = DatabaseService(dbPath: ":memory:")
        try await databaseService.runMigrations()
        viewModel = ChatViewModel(databaseService: databaseService)
    }

    func testNewSessionSavesPrevious() async throws {
        // Arrange - Add message to current session
        let originalSessionId = viewModel.currentSession.id
        await viewModel.sendMessage("Test message")

        // Act - Create new session
        viewModel.newSession()

        // Wait for async save
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Assert - Previous session saved
        let loaded = try await databaseService.loadSessions()
        XCTAssertTrue(loaded.contains(where: { $0.id == originalSessionId }))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testNewSessionSavesPrevious`
Expected: FAIL - ChatViewModel doesn't save on newSession

**Step 3: Commit failing test**

```bash
git add Tests/SeleneChatTests/ChatViewModelTests.swift
git commit -m "test: add failing test for session persistence

RED: ChatViewModel doesn't persist sessions yet.
"
```

### Task 10.2: Add Persistence to ChatViewModel

**Files:**
- Modify: `Sources/Services/ChatViewModel.swift`

**Step 1: Update newSession method**

Find the `newSession()` method and add persistence:

```swift
func newSession() {
    // Save current session before switching
    Task {
        do {
            try await databaseService.saveSession(currentSession)
        } catch {
            print("Failed to save session: \(error)")
            // Don't block - continue with new session
        }
    }

    // Create new session
    currentSession = ChatSession(
        id: UUID(),
        title: "New Chat",
        messages: [],
        createdAt: Date(),
        updatedAt: Date()
    )
    sessions.append(currentSession)
}
```

**Step 2: Update loadSession method**

Find `loadSession(_:)` and add persistence:

```swift
func loadSession(_ session: ChatSession) {
    // Save current session before switching
    Task {
        do {
            try await databaseService.saveSession(currentSession)
        } catch {
            print("Failed to save session: \(error)")
        }
    }

    currentSession = session
}
```

**Step 3: Add session loading on init**

Update initializer:

```swift
init(databaseService: DatabaseService) {
    self.databaseService = databaseService

    // Load persisted sessions
    Task {
        do {
            let loaded = try await databaseService.loadSessions()
            if !loaded.isEmpty {
                sessions = loaded
                currentSession = loaded[0]
            }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter testNewSessionSavesPrevious`
Expected: GREEN

**Step 5: Commit**

```bash
git add Sources/Services/ChatViewModel.swift
git commit -m "feat: add session persistence to ChatViewModel

GREEN: Sessions save on switch, load on init.
Graceful degradation if save fails.
"
```

---

## Phase 11: UI - Pin Button in SessionHistoryView

### Task 11.1: Add Pin Button to Session History

**Files:**
- Modify: `Sources/Views/ChatView.swift` (SessionHistoryView section)

**Step 1: Add pin button to session row**

Find the SessionHistoryView and update the ForEach loop:

```swift
ForEach(chatViewModel.sessions.sorted(by: { $0.updatedAt > $1.updatedAt })) { session in
    HStack {
        Button(action: {
            chatViewModel.loadSession(session)
            dismiss()
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title)
                        .font(.headline)

                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                    }
                }

                HStack {
                    Text(session.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Compression state badge
                    switch session.compressionState {
                    case .full:
                        Text("Full")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    case .compressed:
                        Text("Summary")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(3)
                    case .processing:
                        Text("Processing")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }

                    Text("\(session.messages.count) messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)

        Spacer()

        // Pin toggle button
        Button(action: {
            Task {
                try? await chatViewModel.togglePin(for: session)
            }
        }) {
            Image(systemName: session.isPinned ? "pin.fill" : "pin")
                .foregroundColor(session.isPinned ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(session.isPinned ? "Unpin session" : "Pin session")
    }
}
```

**Step 2: Add togglePin method to ChatViewModel**

Add to ChatViewModel:

```swift
func togglePin(for session: ChatSession) async throws {
    let newPinState = !session.isPinned
    try await databaseService.updateSessionPin(sessionId: session.id, isPinned: newPinState)

    // Update in-memory session
    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
        sessions[index].isPinned = newPinState
        if currentSession.id == session.id {
            currentSession.isPinned = newPinState
        }
    }
}
```

**Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds

**Step 4: Manual test**
- Run app: `swift run SeleneChat`
- Open session history
- Verify pin button appears
- Click pin button
- Verify pin state persists

**Step 5: Commit**

```bash
git add Sources/Views/ChatView.swift Sources/Services/ChatViewModel.swift
git commit -m "feat: add pin button to session history

Users can now pin important sessions to prevent compression.
Shows compression state badges (Full/Summary/Processing).
"
```

---

## Phase 12: Background Compression Integration

### Task 12.1: Add Compression Service to App

**Files:**
- Modify: `Sources/App/SeleneChatApp.swift`

**Step 1: Add CompressionService to app**

Update SeleneChatApp:

```swift
@main
struct SeleneChatApp: App {
    @StateObject private var databaseService = DatabaseService()
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var compressionService: CompressionService

    init() {
        let db = DatabaseService()
        _databaseService = StateObject(wrappedValue: db)
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(databaseService: db))
        _compressionService = StateObject(wrappedValue: CompressionService(databaseService: db))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseService)
                .environmentObject(chatViewModel)
                .task {
                    // Run migrations on startup
                    try? await databaseService.runMigrations()

                    // Check for sessions to compress
                    await compressionService.checkAndCompressSessions()
                }
        }
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/App/SeleneChatApp.swift
git commit -m "feat: integrate CompressionService on app launch

Runs migrations and compression check at startup.
"
```

---

## Phase 13: E2E Manual Testing

### Task 13.1: Complete Lifecycle Test

**Files:**
- None (manual testing)

**Step 1: Test complete lifecycle**

```bash
# Build and run
swift build
swift run SeleneChat
```

**Test steps:**
1. Send a message in current session
2. Click "New Chat" button
3. Verify new session created
4. Send another message
5. Close app
6. Reopen app
7. Verify both sessions appear in history
8. Verify messages preserved

**Expected:** All sessions persist correctly

**Step 2: Test pin functionality**

1. Open session history
2. Pin a session
3. Close and reopen app
4. Verify session still pinned

**Expected:** Pin state persists

**Step 3: Test compression (simulated)**

```bash
# Open SQLite and manually set old date
sqlite3 /selene/data/selene.db
# UPDATE chat_sessions SET created_at = '2024-10-01T00:00:00Z' WHERE id = '<some-uuid>';
# .quit

# Rerun app to trigger compression
swift run SeleneChat
```

**Expected:** Old session compresses to summary

**Step 4: Document any issues**

Create file if issues found: `TESTING-NOTES.md`

### Task 13.2: Create Final Commit

**Step 1: Run all tests**

Run: `swift test`
Expected: All tests pass

**Step 2: Final commit**

```bash
git add -A
git commit -m "test: verify E2E session persistence workflow

Manual testing complete:
- Session creation and switching ✅
- Message persistence ✅
- Pin functionality ✅
- Compression workflow ✅ (simulated)

Ready for code review.
"
```

---

## Phase 14: Finishing Up

### Task 14.1: Use Finishing Skill

**Required sub-skill:** Use `superpowers:finishing-a-development-branch`

This skill will:
1. Verify all tests pass
2. Review commits
3. Present merge options (merge to main, create PR, or cleanup)
4. Clean up worktree after decision

---

## Verification Checklist

Before calling finished:

- [ ] All tests pass (`swift test`)
- [ ] App builds without errors (`swift build`)
- [ ] Manual testing complete (session persistence, pin, compression)
- [ ] All files committed
- [ ] No debug code or TODOs left
- [ ] Design document matches implementation

---

## Common Issues & Solutions

**Issue: Test times out**
- Solution: Check async/await patterns, ensure Task.sleep durations reasonable

**Issue: JSON encoding fails**
- Solution: Verify Message and ChatSession conform to Codable properly

**Issue: Database connection fails**
- Solution: Check dbPath is valid, directory exists

**Issue: Sessions don't persist**
- Solution: Verify saveSession is called, check for error logs

**Issue: Compression never triggers**
- Solution: Check date math (30-day threshold), verify query logic

---

## Next Steps After Implementation

1. **Code Review**: Use `superpowers:requesting-code-review` to review against design
2. **Documentation**: Update README with new persistence features
3. **Testing**: Add more edge case tests as needed
4. **Integration**: Consider enabling n8n integration (Phase 2 of design)

---

**End of Plan**
