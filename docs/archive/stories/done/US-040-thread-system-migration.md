# US-040: Thread System Database Migration

**Status:** done
**Priority:** critical
**Effort:** S
**Phase:** thread-system-1
**Created:** 2026-01-04
**Completed:** 2026-01-04

---

## User Story

As a **Selene system**,
I want **database tables to store note embeddings, associations, and threads**,
So that **the thread system has the foundation to track semantic relationships between notes**.

---

## Context

This is the foundation for the entire thread system. Without these tables, nothing else can work. The migration creates:

- `note_embeddings` - Vector storage for each note (768-dim from nomic-embed-text)
- `note_associations` - Pairwise similarity links between notes
- `threads` - Emergent clusters of related thinking
- `thread_notes` - Many-to-many link between threads and notes
- `thread_history` - Track how threads evolve over time

This is pure infrastructure - no user-facing changes, but critical for Phase 1.

---

## Acceptance Criteria

- [x] Migration file created at `database/migrations/013_thread_system.sql`
- [x] All 5 tables created with correct schema (per design doc)
- [x] Indexes created for performance (embeddings by note_id, associations by score, etc.)
- [x] Migration runs successfully on production database
- [x] Existing data is unaffected (additive change only)
- [x] Schema documented in `database/schema.sql`

---

## ADHD Design Check

- [x] **Reduces friction?** N/A - infrastructure
- [x] **Visible?** N/A - infrastructure
- [x] **Externalizes cognition?** Foundation for thread system which holds thoughts for user

---

## Technical Notes

- Dependencies: None (first story in Phase 1)
- Affected components:
  - `database/migrations/013_thread_system.sql` (new)
  - `database/schema.sql` (update)
- Design doc: `docs/plans/2026-01-04-selene-thread-system-design.md`

**Schema from design doc:**
```sql
-- See design doc "New Database Tables" section for full schema
-- Key tables: note_embeddings, note_associations, threads, thread_notes, thread_history
```

---

## Links

- **Branch:** `US-040/thread-system-migration` (merged)
- **PR:** https://github.com/SlowSpeedChase/selene/pull/21
