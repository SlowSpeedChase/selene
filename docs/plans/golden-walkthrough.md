# Golden Walkthrough — Manual Test Script

**Purpose:** End-to-end verification of SeleneChat core features against the dev database. Run after significant changes to catch UX regressions.

## Prerequisites

1. Dev SeleneChat running from CLI: `cd SeleneChat && swift build && .build/debug/SeleneChat`
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
