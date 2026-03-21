# Close the Loop — Unified Task-Thread Feedback

**Status:** Ready
**Created:** 2026-03-21
**Topic:** executive-function, threads, things-integration

---

## Problem

Selene captures thoughts, extracts tasks, and sends them to Things 3 — but when you complete a task, Selene has no idea. Thread momentum is driven only by note volume, not action. The morning briefing can't show progress. Three disconnected table systems (semantic threads, task_links, discussion_threads) were built at different times and never wired together.

The result: Selene is a smart notebook, not an executive function partner. The loop from "thought → task → completion → updated context" is broken.

---

## Solution

Unify the three systems with a single `thread_activity` table, link tasks to semantic threads, rewrite the Things sync as TypeScript, and schedule it. Silent background sync — no user action required.

---

## Architecture

### Data Flow (After)

```
Note → extract-tasks → Things task created
                      → task_links (with thread_id)
                      → task_metadata (energy, overwhelm, etc.)
                      → thread_activity: 'task_created'

         ... user works in Things ...

sync-things-status (every 15 min) → polls Things via AppleScript
  → task_links.things_status = 'completed'
  → thread_activity: 'task_completed'
  → threads.last_activity_at updated

reconsolidate-threads (hourly) → calculates momentum
  → notes_7d × 2 + notes_30d × 1 + tasks_completed_7d × 3
  → Briefing naturally shows accurate thread progress
```

### New: `thread_activity` Table

Every meaningful event on a thread goes here. One table, one index query for momentum.

```sql
CREATE TABLE thread_activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    activity_type TEXT NOT NULL CHECK(activity_type IN (
        'note_added', 'task_created', 'task_completed',
        'thread_split', 'thread_merged', 'thread_archived',
        'thread_reactivated', 'discussion_created'
    )),
    raw_note_id INTEGER,
    things_task_id TEXT,
    metadata TEXT,  -- JSON for extra context
    occurred_at TEXT DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL
);
CREATE INDEX idx_thread_activity_thread ON thread_activity(thread_id);
CREATE INDEX idx_thread_activity_type ON thread_activity(activity_type);
CREATE INDEX idx_thread_activity_occurred ON thread_activity(occurred_at DESC);
```

### Modified: `task_links` Table

Add semantic thread reference alongside existing `discussion_thread_id`:

```sql
ALTER TABLE task_links ADD COLUMN thread_id INTEGER REFERENCES threads(id);
CREATE INDEX idx_task_links_semantic_thread ON task_links(thread_id);
```

---

## Components

### 1. Database Migration

New migration creates `thread_activity` and adds `thread_id` to `task_links`.

### 2. `extract-tasks.ts` Changes

- After extracting a task, look up `thread_notes` for the source `raw_note_id`
- If thread found, store `thread_id` on `task_links`
- Insert `task_created` event into `thread_activity`
- Populate `task_metadata` table (energy, overwhelm, type — LLM already extracts this, just never stored)
- Fix pending directory path to `scripts/things-bridge/pending/`

**Timing edge case:** Thread detection runs every 30 min, task extraction every 5 min. A note may not have a thread yet. Solution: skip — backfill in reconsolidate.

### 3. `sync-things-status.ts` (New TypeScript Workflow)

Replaces `sync-things-status.sh`. Consistent with all other workflows.

- Queries `task_links` for `things_status = 'open'`
- Calls existing `get-task-status.scpt` via `execFileSync` for each task
- When completion detected:
  - Update `task_links.things_status = 'completed'`, `things_completed_at`
  - If `thread_id` exists, insert `thread_activity` record (`task_completed`)
  - Update `threads.last_activity_at`
- Scheduled via new launchd plist, every 15 minutes

### 4. `reconsolidate-threads.ts` Backfill

During hourly reconsolidation, after thread membership is updated:

- Query `task_links` where `thread_id IS NULL` and `raw_note_id` is in this thread's `thread_notes`
- Update those `task_links.thread_id`
- If any are already completed, insert retroactive `thread_activity` records

### 5. `process-pending-tasks.sh` Fix

Update watch path to match `scripts/things-bridge/pending/` (where files actually are).

### 6. Launchd Plist

New `com.selene.sync-things-status.plist` — every 15 minutes.

---

## Momentum Formula

Already correct in `reconsolidate-threads.ts`:

```
momentum = (notes_7_days × 2) + (notes_30_days × 1) + (tasks_completed_7_days × 3)
```

Currently `tasks_completed_7_days` is always 0 because `thread_activity` doesn't exist. Once it does, momentum reflects reality with no formula change.

---

## Briefing Impact

No SeleneChat code changes needed. `BriefingViewModel` already:
- Identifies stalled threads (no activity in 5 days) — `last_activity_at` now updated on task completion
- Queries `getTasksForThread()` — task_links now linked to semantic threads
- Shows open task counts — naturally accurate once data flows

---

## Files Changed

| File | Change |
|------|--------|
| `database/migrations/022_thread_activity.sql` | New migration |
| `src/workflows/extract-tasks.ts` | Thread linking, task_metadata population, path fix |
| `src/workflows/sync-things-status.ts` | New TypeScript workflow |
| `src/workflows/reconsolidate-threads.ts` | Backfill unlinked task_links |
| `scripts/things-bridge/process-pending-tasks.sh` | Fix watch path |
| `launchd/com.selene.sync-things-status.plist` | New plist, every 15 min |

---

## Out of Scope

- No SeleneChat UI changes
- No SeleneMobile changes
- No proactive coaching/nudges (Phase C, future)
- No new capture sources
- No changes to Things task creation AppleScript
- No retroactive enrichment of old completed tasks (backfill handles future orphans only)

---

## Future: Phase C (Executive Coaching)

This design creates the foundation for proactive recommendations:
- `thread_activity` provides a complete timeline per thread
- `task_metadata` has energy, overwhelm, and time estimates
- Momentum reflects real progress
- A future coaching layer can reason over: "3 tasks completed this week on Thread X, 2 open, user has low energy → suggest the 15-min research task, not the 2-hour planning task"

---

## Acceptance Criteria

- [ ] Tasks created from notes are linked to their semantic thread (when one exists)
- [ ] `task_metadata` is populated with energy, overwhelm, and type data
- [ ] Things task completions are detected within 15 minutes
- [ ] Completed tasks generate `thread_activity` records
- [ ] Thread momentum reflects task completions (3× weight)
- [ ] Briefing shows accurate open/completed task counts per thread
- [ ] Backfill links orphaned tasks to threads during reconsolidation
- [ ] Pending directory path is consistent across extract and process scripts

---

## ADHD Check

- [x] **Reduces friction?** Fully silent, zero user action required
- [x] **Externalizes cognition?** Thread momentum reflects real progress, not just notes
- [x] **Makes information visible?** Briefing shows what you've actually accomplished
- [x] **Realistic?** 15-min polling, no complex automations to maintain

---

## Scope

~3-4 days focused work.

---

## Links

- **Branch:** (added when implementation starts)
- **PR:** (added when complete)
- **Depends on:** Existing Things bridge (`scripts/things-bridge/`)
- **Enables:** Phase C executive coaching (future design)
