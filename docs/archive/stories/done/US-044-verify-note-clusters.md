# US-044: Verify Note Clusters Forming

**Status:** active
**Priority:** high
**Effort:** S
**Phase:** thread-system-1
**Created:** 2026-01-04
**Updated:** 2026-01-06
**Branch:** US-044/verify-note-clusters

---

## User Story

As a **Selene developer**,
I want **to query and visualize note clusters from the association data**,
So that **I can verify the foundation works before building thread detection**.

---

## Context

Phase 1 checkpoint: Before building thread detection (Phase 2), we need to verify that:
1. Embeddings are being generated correctly
2. Associations are capturing meaningful relationships
3. Clusters are forming naturally in the data

This story creates verification tools - queries, scripts, maybe a simple visualization.

**Key question to answer:** "Given a note, what similar notes does the system find?"

---

## Acceptance Criteria

- [x] Query script created: `scripts/query-similar-notes.sh <note_id>`
- [x] Script returns top N similar notes with similarity scores
- [x] Manual verification: results make semantic sense
- [x] Cluster stats query: "How many notes have 3+ associations?"
- [x] Documentation of verification results in Phase 1 completion notes
- [x] At least 10 sample queries verified manually

---

## ADHD Design Check

- [x] **Reduces friction?** Quick command to explore data
- [x] **Visible?** Makes the invisible embedding space visible
- [x] **Externalizes cognition?** Shows connections that exist in user's thinking

---

## Technical Notes

- Dependencies: US-040, US-041, US-042, US-043 (all prior Phase 1 stories)
- Affected components:
  - `scripts/query-similar-notes.sh` (new)
  - `scripts/cluster-stats.sh` (new)
  - `scripts/CLAUDE.md` (update)
- Design doc: `docs/plans/2026-01-04-selene-thread-system-design.md`

**Sample queries:**
```sql
-- Find similar notes to note ID 123
SELECT
    rn.id,
    rn.title,
    SUBSTR(rn.content, 1, 100) as preview,
    na.similarity_score
FROM note_associations na
JOIN raw_notes rn ON rn.id = na.note_b_id
WHERE na.note_a_id = 123
ORDER BY na.similarity_score DESC
LIMIT 10;

-- Cluster stats
SELECT
    COUNT(*) as notes_with_associations,
    AVG(assoc_count) as avg_associations
FROM (
    SELECT note_a_id, COUNT(*) as assoc_count
    FROM note_associations
    GROUP BY note_a_id
) sub;
```

---

## Phase 1 Completion Criteria

When this story is done, Phase 1 is complete. Checkpoint:
- [x] All notes have embeddings (64/65 notes - 98%)
- [x] Associations computed for all embedded notes (21 associations)
- [x] Can query "similar notes" and get meaningful results
- [x] Ready to proceed to Phase 2 (Thread Detection)

---

## Verification Results (2026-01-06)

### Data Summary

| Metric | Value |
|--------|-------|
| Total production notes | 65 |
| Notes with embeddings | 64 (98%) |
| Total associations | 21 |
| Similarity threshold | 0.7 |
| Max similarity | 0.849 |
| Avg similarity | 0.742 |

### Cluster Distribution

| Category | Notes |
|----------|-------|
| 5+ associations (highly connected) | 1 |
| 3-4 associations (clustered) | 3 |
| 1-2 associations (some connections) | 19 |

### Sample Query Verification (10/10)

All queries returned semantically meaningful results:

1. **Party engagement notes** (21, 22, 208) - correctly grouped social skills topics
2. **Selene project notes** (59, 61, 65, 94, 126) - correctly grouped app development ideas
3. **Dog training notes** (41, 54, 60) - correctly grouped Leo-related notes
4. **Project management** (65, 126) - highest similarity (0.849) for same-topic notes

### Scripts Created

- `scripts/query-similar-notes.sh <note_id> [limit]` - Query similar notes
- `scripts/cluster-stats.sh` - Show cluster statistics

### Workflow Fix

Fixed `process.env` → `$env` in workflow 11-Association-Computation for n8n 1.110.1 compatibility.

---

## Links

- **Branch:** US-044/verify-note-clusters
- **PR:** https://github.com/SlowSpeedChase/selene/pull/26
