# SeleneChat Database Integration - Design Document

**Created:** 2025-11-14
**Status:** Design Complete - Ready for Implementation
**Goal:** Store chat sessions in Selene database for ADHD memory support

---

## Overview

### Purpose

Enable SeleneChat to persist conversation history to the Selene database, supporting the ADHD use case: "what did I search for before?" Store full conversation history for 30 days, then automatically compress to on-device AI summaries for long-term storage.

### Core Strategy

- **Capture**: Full chat messages stored in-memory and persisted to database
- **Retention**: 30-day full message retention, then compress to summary
- **Privacy**: All processing on-device using Apple Intelligence
- **Separation**: Chat data isolated from note processing (can integrate later if needed)
- **Retrieval**: Simple chronological browsing of session history

---

## Architecture

### Components

1. **ChatViewModel** - Enhanced with persistence hooks on session close/switch
2. **DatabaseService** - New CRUD methods for chat session operations
3. **ChatSession model** - Added `isPinned`, `compressionState`, `summaryText` fields
4. **CompressionService** - Background task monitors sessions > 30 days, compresses via Apple Intelligence
5. **Database schema** - New `chat_sessions` table in existing `selene.db`

### Data Flow

```
1. User chats → Messages accumulate in-memory (ChatSession)
2. User switches session/closes app → ChatViewModel.saveSession()
3. Background task checks sessions > 30 days old
4. Non-pinned old sessions → Compress to summary (Apple Intelligence)
5. User browses history → Chronological list from database
```

### Privacy Model

- Everything stays on-device
- Apple Intelligence summarization runs locally
- No external API calls
- Aligns with existing privacy tier architecture

---

## Database Schema

### New Table: `chat_sessions`

```sql
CREATE TABLE chat_sessions (
    id TEXT PRIMARY KEY,              -- UUID from ChatSession
    title TEXT NOT NULL,              -- Session title
    created_at TEXT NOT NULL,         -- ISO 8601 timestamp
    updated_at TEXT NOT NULL,         -- ISO 8601 timestamp
    message_count INTEGER NOT NULL,   -- Number of messages in session

    -- Retention and compression
    is_pinned INTEGER DEFAULT 0,      -- 1 = keep full messages forever, 0 = compress after 30 days
    compression_state TEXT DEFAULT 'full',  -- 'full' | 'compressed' | 'processing'
    compressed_at TEXT,               -- When compression happened (if applicable)

    -- Content (mutually exclusive based on compression_state)
    full_messages_json TEXT,          -- JSON array of Message objects (when compression_state = 'full')
    summary_text TEXT                 -- AI-generated summary (when compression_state = 'compressed')
);

CREATE INDEX idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
CREATE INDEX idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);
```

### Design Decisions

- **JSON blob storage**: Simple, matches Swift Codable serialization
- **compression_state lifecycle**: `full` → `processing` → `compressed`
- **Separate columns**: Avoid parsing complexity by separating full vs compressed
- **Indexes**: Support chronological browsing and compression queries
- **is_pinned flag**: Users can protect important sessions from compression
- **Database location**: Use existing `/selene/data/selene.db`

---

## Swift Implementation

### ChatSession Model Enhancement

**File**: `Sources/Models/ChatSession.swift`

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

    enum CompressionState: String, Codable {
        case full          // Full messages available
        case processing    // Compression in progress
        case compressed    // Only summary available
    }
}
```

### DatabaseService Additions

**File**: `Sources/Services/DatabaseService.swift`

New methods:

```swift
// Core CRUD operations
func saveSession(_ session: ChatSession) async throws
func loadSessions() async throws -> [ChatSession]
func deleteSession(_ session: ChatSession) async throws

// Pin management
func updateSessionPin(sessionId: UUID, isPinned: Bool) async throws

// Compression support
func getSessionsReadyForCompression() async throws -> [ChatSession]  // > 30 days, not pinned, state = full
func compressSession(sessionId: UUID, summary: String) async throws  // Transition to compressed state
func updateCompressionState(sessionId: UUID, state: CompressionState) async throws
```

### ChatViewModel Changes

**File**: `Sources/Services/ChatViewModel.swift`

Persistence hooks:

```swift
func newSession() {
    Task {
        try? await databaseService.saveSession(currentSession)  // Save before switching
    }
    // ... existing new session logic
}

func loadSession(_ session: ChatSession) {
    Task {
        try? await databaseService.saveSession(currentSession)  // Save current before loading
    }
    // ... existing load logic
}

// Load persisted sessions on init
init(databaseService: DatabaseService) {
    Task {
        sessions = try await databaseService.loadSessions()
    }
}
```

### CompressionService (New Component)

**File**: `Sources/Services/CompressionService.swift`

```swift
import Foundation
import NaturalLanguage

@MainActor
class CompressionService: ObservableObject {
    private let databaseService: DatabaseService
    private var compressionTask: Task<Void, Never>?

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // Called during app idle time or on launch
    func checkAndCompressSessions() async {
        let sessions = try? await databaseService.getSessionsReadyForCompression()

        guard let sessions = sessions, !sessions.isEmpty else { return }

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

        // Generate summary using Apple Intelligence
        let summary = await generateSummary(for: session)

        // Save compressed version
        try? await databaseService.compressSession(
            sessionId: session.id,
            summary: summary
        )
    }

    private func generateSummary(for session: ChatSession) async -> String {
        // Use NLLanguageModel for on-device summarization
        // Fallback: extract user queries + key assistant responses
        let userQueries = session.messages
            .filter { $0.role == .user }
            .map { $0.content }

        let summary = """
        Session: \(session.title)
        Date: \(session.formattedDate)
        Questions asked: \(userQueries.count)

        Key queries:
        \(userQueries.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
        """

        return summary
    }
}
```

**Integration points**:
- Call `checkAndCompressSessions()` on app launch
- Call during app idle (NSWorkspace notifications on macOS)
- Async/non-blocking - won't slow down UI

**Compression logic**:
- Initial implementation: Extract user queries + metadata
- Future enhancement: Use Apple's summarization APIs when available
- Graceful degradation: If summarization fails, keep full messages

---

## Testing Strategy

### Layer 1: Unit Tests - Database Operations

**File**: `SeleneChat/Tests/DatabaseServiceTests.swift`

```swift
class ChatSessionPersistenceTests: XCTestCase {
    var databaseService: DatabaseService!

    // Core CRUD operations
    func testSaveAndLoadSession() async throws
    func testUpdateSessionPin() async throws
    func testDeleteSession() async throws

    // Compression workflow
    func testGetSessionsReadyForCompression() async throws  // Verify 30-day threshold
    func testCompressSession() async throws                 // Verify state transition
    func testPinnedSessionsNotReturned() async throws       // Pinned = excluded from compression

    // Edge cases
    func testSaveEmptySession() async throws
    func testConcurrentSessionSaves() async throws          // Race condition handling
    func testCorruptedJSONHandling() async throws
}
```

### Layer 2: Integration Tests - ChatViewModel Persistence

**File**: `SeleneChat/Tests/ChatViewModelTests.swift`

```swift
class ChatSessionLifecycleTests: XCTestCase {
    var viewModel: ChatViewModel!
    var mockDatabase: DatabaseService!

    // Session switching
    func testNewSessionSavesPrevious() async throws
    func testLoadSessionPersistsCurrent() async throws

    // Message accumulation
    func testMessagesPersistedOnSessionSwitch() async throws
    func testMessageCountAccurate() async throws

    // Compression integration
    func testCompressedSessionLoadsWithSummary() async throws
    func testFullSessionLoadsWithMessages() async throws
}
```

### Layer 3: UI Tests - Session History View

**File**: `SeleneChat/Tests/SessionHistoryUITests.swift`

```swift
class SessionHistoryViewTests: XCTestCase {
    // Display
    func testSessionsDisplayChronologically() throws
    func testPinnedSessionShowsIndicator() throws

    // Interaction
    func testLoadSessionFromHistory() throws
    func testDeleteSessionRemovesFromList() throws
    func testPinSessionPersists() throws
}
```

### Layer 4: End-to-End Acceptance Tests

**File**: `SeleneChat/Tests/ChatPersistenceE2ETests.swift`

```swift
class ChatPersistenceE2ETests: XCTestCase {
    // Happy path
    func testCompleteChatSessionLifecycle() async throws {
        // 1. Create session, send messages
        // 2. Switch to new session (triggers save)
        // 3. Quit and relaunch app
        // 4. Verify session loaded from database
        // 5. Verify messages intact
    }

    // Compression workflow
    func testThirtyDayCompressionWorkflow() async throws {
        // 1. Create session with created_at = 31 days ago
        // 2. Run compression check
        // 3. Verify state = compressed
        // 4. Verify summary_text populated
        // 5. Verify full_messages_json = null
    }

    // App crash recovery
    func testAppCrashBeforeSave() async throws {
        // 1. Create session with messages
        // 2. Simulate crash (don't call save)
        // 3. Verify session not in database
        // 4. Accept data loss for unsaved in-memory state
    }
}
```

---

## Error Handling

### Graceful Degradation Strategy

Never block user from chatting if persistence fails:

```swift
enum ChatPersistenceError: Error {
    case databaseUnavailable
    case serializationFailed
    case compressionFailed
    case sessionNotFound
}

// In ChatViewModel
func newSession() {
    Task {
        do {
            try await databaseService.saveSession(currentSession)
        } catch {
            // Log error but don't block UI
            print("Failed to save session: \(error)")
            // Session still exists in-memory, user can continue chatting
        }
    }
    // Continue with new session creation
}
```

**Philosophy**: Chat functionality always works. Persistence is a nice-to-have enhancement that fails silently.

---

## Database Migration

### Migration File

**File**: `database/migrations/005_add_chat_sessions.sql`

```sql
-- Migration: Add chat session storage
-- Date: 2025-11-14

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

CREATE INDEX idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
CREATE INDEX idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);
```

### Rollback Plan

Chat sessions table is isolated from notes processing. Can be dropped without affecting core Selene functionality:

```sql
DROP TABLE IF EXISTS chat_sessions;
```

---

## Implementation Plan

### Test-Driven Development Order

**Phase 1: Database Layer (TDD)**
1. Write failing test: `testSaveAndLoadSession()`
2. Create migration SQL file (`005_add_chat_sessions.sql`)
3. Implement `DatabaseService.saveSession()` → GREEN
4. Implement `DatabaseService.loadSessions()` → GREEN
5. Write + implement remaining CRUD tests (pin, delete, etc.)

**Phase 2: Compression Service (TDD)**
6. Write failing test: `testGetSessionsReadyForCompression()`
7. Implement query logic → GREEN
8. Write failing test: `testCompressSession()`
9. Implement `CompressionService` with basic summarization → GREEN
10. Test pinned sessions exclusion

**Phase 3: ViewModel Integration (TDD)**
11. Write failing test: `testNewSessionSavesPrevious()`
12. Add persistence hooks to `ChatViewModel` → GREEN
13. Test session loading on app launch
14. Test concurrent save scenarios

**Phase 4: UI Updates**
15. Add pin button to `SessionHistoryView`
16. Add compression state indicator (badge showing "Full" vs "Summary")
17. Show summary text for compressed sessions
18. UI tests for interaction

**Phase 5: E2E Validation**
19. Manual testing: Create session, switch, verify persistence
20. Manual testing: Set `created_at` to 31 days ago, verify compression
21. Run full test suite
22. Performance testing: 100 sessions, verify load time acceptable

---

## Future Enhancements (Out of Scope)

These are explicitly NOT part of this implementation but could be added later:

1. **Integration with n8n pattern detection** - Export chat summaries as synthetic notes
2. **Advanced Apple Intelligence summarization** - Use newer APIs when available
3. **Search interface** - Keyword search across session summaries
4. **Query pattern analysis** - Detect "asks about projects on Monday mornings" patterns
5. **Export to Obsidian** - Generate markdown files from chat history
6. **Configurable retention period** - Let users set 7/14/30/60/90 day thresholds

---

## Success Criteria

### Feature Complete When:

- ✅ Chat sessions persist to database on session switch
- ✅ Sessions load from database on app launch
- ✅ Sessions older than 30 days compress to summaries
- ✅ Pinned sessions never compress
- ✅ All 4 test layers pass (unit, integration, UI, E2E)
- ✅ App never crashes or blocks UI due to persistence failures
- ✅ Chronological session history displays correctly
- ✅ Performance acceptable with 100+ sessions

### Known Limitations:

- **Data loss on crash**: If app crashes before session switch, in-memory messages lost (acceptable trade-off for batch write strategy)
- **Basic summarization**: Initial implementation uses simple query extraction, not advanced AI summarization
- **No search**: Must browse chronologically to find old sessions
- **No n8n integration**: Chat data isolated from note processing workflows

---

## Questions & Decisions Log

| Question | Decision | Rationale |
|----------|----------|-----------|
| How much detail to store? | Hybrid: full 30 days, then summary | Balance rich data with privacy/storage |
| Summarization mechanism? | On-device Apple Intelligence | Privacy-first, consistent with existing tiers |
| When to write to DB? | On session close/switch (batch) | Performance vs. reliability balance |
| Integrate with n8n patterns? | Not yet - separate tracking | Avoid complexity, preserve options |
| What metadata to capture? | Minimal: id, timestamps, message_count, content | Lean schema for future parseability |
| Retention policy mechanism? | Background automatic with pin override | Automation + user control for important sessions |
| Testing strategy? | Layered pyramid (unit → E2E) | Comprehensive confidence across all layers |
| Retrieval interface? | Chronological list only | Simple, familiar, low cognitive overhead |

---

## References

- **Existing codebase**: `/Users/chaseeasterling/selene/SeleneChat/`
- **Database**: `/selene/data/selene.db` (SQLite)
- **Related roadmap phase**: [SeleneChat Enhancements](../roadmap/02-CURRENT-STATUS.md#-selenechat-enhancements)
- **Privacy architecture**: See `PrivacyRouter.swift` for tier system

---

**Next Steps**: Ready for implementation using git worktree + detailed implementation plan.
