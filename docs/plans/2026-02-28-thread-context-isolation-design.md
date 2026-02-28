# Thread Context Isolation + Golden Walkthrough

**Date:** 2026-02-28
**Status:** Ready
**Scope:** Bug fixes + testing infrastructure

## Problem

End-to-end user testing of SeleneChat revealed three issues that compound into a broken thread workspace experience:

1. **Thread workspace leaks context across threads.** Asking about a packing list in the Joshua Tree thread pulls in ceramics notes because a global fallback searches all 536 notes when thread-scoped similarity is below 0.5.

2. **Conversation memories are global and thread-unaware.** The hallucinated ceramics context from (1) gets saved as "facts" in `conversation_memories`, which then contaminate future sessions in any thread.

3. **New projects default to parked status.** `ProjectService.createProject()` hardcodes `status = "parked"`, so user-created projects never appear in Active Projects (collapsed Parked section at bottom).

## Root Causes

### Finding 1: Global Fallback in Chunk Retrieval

**File:** `SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift:284-299`

```swift
// If thread-scoped results are poor, try global fallback
if results.isEmpty || (results.first?.similarity ?? 0) < 0.5 {
    let allCandidates = try await databaseService.getAllChunksWithEmbeddings()
    // ... searches ALL notes across ALL threads
}
```

When the best thread-scoped chunk scores below 0.5 similarity, the system falls back to searching every note in the database. With 536 dev notes and permissive thresholds (minSimilarity: 0.3), loosely related content from unrelated threads passes the filter.

### Finding 2: Unscoped Memory Extraction

**File:** `SeleneChat/Sources/SeleneChat/Services/ChatViewModel.swift:804-808`

Memories are extracted from LLM responses and stored globally in `conversation_memories` with no thread association. When retrieved for a new thread workspace session, all memories match regardless of origin.

The contamination chain: global fallback pulls ceramics into Joshua Tree context -> LLM generates response mentioning ceramics -> memory extraction saves "user has ceramics studio" as a fact -> ceramics thread retrieves this memory and treats it as established context.

### Finding 3: Hardcoded Parked Status

**File:** `SeleneChat/Sources/SeleneChat/Services/ProjectService.swift:178`

```swift
projectStatus <- "parked"
```

The schema default is also `parked`. User-initiated project creation should produce active projects.

## Design

### Fix 1: Remove Global Fallback

**Change:** Delete the global fallback block in `ThreadWorkspaceChatViewModel.retrieveChunksForQuery()` (lines 284-299). If thread-scoped chunks have low similarity, return them anyway. If none exist, return empty and let the existing `buildPrompt(for:)` fallback use the thread's full notes via `ThinkingPartnerContextBuilder.buildDeepDiveContext()`.

**Rationale:** The thread workspace is intentionally scoped. Low similarity within a thread is expected for novel queries (like "packing list" in a thread about hiking plans). The full-notes fallback already handles this gracefully. Cross-thread retrieval should only happen when explicitly requested by the user.

### Fix 2: Thread-Scoped Memories

**Two changes:**

a) **Schema:** Add `thread_id INTEGER` column to `conversation_memories` (nullable, FK to threads). General chat memories stay null. Thread workspace memories get tagged.

b) **Retrieval:** When building prompts in `ThreadWorkspaceChatViewModel`, pass `threadId` to memory retrieval. Filter to memories matching that thread OR having null thread_id (global facts).

c) **Extraction:** When `ChatViewModel.extractMemories()` runs from a thread workspace context, include the thread_id in the insert.

**Rationale:** Memories are valuable but must respect thread boundaries. Global memories (from general chat) should still be available everywhere. Thread-specific memories should stay in their thread.

### Fix 3: Active Project Default

**Change:** In `ProjectService.createProject()`, change `projectStatus <- "parked"` to `projectStatus <- "active"`. Set `last_active_at` to current timestamp.

**Rationale:** When a user explicitly creates a project, they intend to work on it. Auto-detected projects from the pipeline can still default to parked via the schema default.

### Golden Walkthrough: Manual Script

A scripted end-to-end test that documents expected behavior. Run after changes to verify the full user experience.

#### Prerequisites
- Dev SeleneChat running (CLI build, uses `~/selene-data-dev/selene.db`)
- Clean conversation memories: `sqlite3 ~/selene-data-dev/selene.db "DELETE FROM conversation_memories;"`
- Clean projects: `sqlite3 ~/selene-data-dev/selene.db "DELETE FROM projects WHERE is_system IS NULL OR is_system = 0;"`

#### Steps

| Step | Action | Expected Result | Verify |
|------|--------|----------------|--------|
| 1 | Open Planning tab | Active Projects section visible, no user projects | Visual |
| 2 | Go to Inbox, create project from a note | Project appears in Active Projects immediately | Visual + `SELECT status FROM projects WHERE name = '...'` returns `active` |
| 3 | Navigate to Threads tab | Thread list shows all 14 threads | Visual |
| 4 | Open Joshua Tree thread workspace | Thread workspace loads with JT summary and notes | Visual |
| 5 | Type "help me make a packing list" | Response references camping gear, hiking, weather. NO ceramics, NO office noise, NO unrelated threads | Read response carefully |
| 6 | Check memories | `SELECT content FROM conversation_memories WHERE thread_id = 5;` shows JT-relevant facts only | SQL query |
| 7 | Navigate back, open Ceramics thread | Fresh workspace, no JT context in UI | Visual |
| 8 | Type "what should I work on next?" | Response references glazing, techniques, studio work. NO camping, NO Joshua Tree | Read response carefully |
| 9 | Check memories again | `SELECT content, thread_id FROM conversation_memories;` shows thread-tagged memories, no cross-contamination | SQL query |

### Golden Walkthrough: Automated Integration Test

**File:** `SeleneChat/Tests/SeleneChatTests/Integration/GoldenWalkthroughTests.swift`

Test cases:

1. **`testCreateProjectDefaultsToActive`** — Call `ProjectService.createProject()`, assert `status == "active"`.

2. **`testThreadScopedChunkRetrieval`** — Set up two threads with distinct notes. Query one thread. Assert retrieved chunks only contain notes from that thread (no global fallback).

3. **`testMemoryExtractionTagsThreadId`** — Simulate memory extraction in thread workspace context. Assert inserted memories have correct `thread_id`.

4. **`testMemoryRetrievalFiltersbyThread`** — Insert memories for thread A and thread B. Retrieve for thread A. Assert only thread A memories (plus global) are returned.

## ADHD Check

- Fixes are focused: 3 surgical changes, no refactoring
- Golden walkthrough provides visual verification (not just green tests)
- Thread isolation reduces cognitive noise (see only what matters in each context)

## Acceptance Criteria

- [ ] Joshua Tree thread workspace never mentions ceramics (or any other unrelated thread)
- [ ] Ceramics thread workspace never mentions Joshua Tree
- [ ] New user-created projects appear in Active Projects immediately
- [ ] Conversation memories are tagged with thread_id when created from thread workspace
- [ ] Memory retrieval in thread workspace filters by thread
- [ ] Golden walkthrough manual script passes end-to-end
- [ ] Golden walkthrough integration tests pass with `swift test`

## Files Changed

| File | Change |
|------|--------|
| `ViewModels/ThreadWorkspaceChatViewModel.swift` | Remove global fallback (lines 284-299) |
| `Services/ProjectService.swift` | Change `"parked"` to `"active"` (line 178) |
| `Services/MemoryService.swift` | Add thread_id parameter to extraction and retrieval |
| `Services/DatabaseService.swift` | Add thread_id column migration, update memory queries |
| `Tests/.../GoldenWalkthroughTests.swift` | New: automated golden walkthrough tests |
| `docs/plans/golden-walkthrough.md` | New: manual walkthrough script |
