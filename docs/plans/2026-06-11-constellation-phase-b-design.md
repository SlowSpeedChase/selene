# Design: Knowledge Constellation Phase B — note↔note friend edges

**Date:** 2026-06-11
**Status:** Ready
**Depends on:** Phase A (shipped), note_connections backfill (done 2026-06-11, 6,794 edges / 336 notes)
**Related:** [[2026-05-29-knowledge-constellation-design]]

---

## What & why

Phase A gave ExcaliBrain a cluster→note hierarchy (`parent::` fields). Phase B adds the
horizontal layer: each note links directly to its top-5 most-similar notes via `friend::` Dataview
fields, letting the user fly note→note without routing through a cluster hub.

The motivating example: a note about sentence-diagramming should surface a `friend::` link to a
note about grammar intuition — a lateral connection the cluster hierarchy can't show.

**Precondition satisfied:** `note_connections` now holds 6,794 edges (cosine ≥ 0.75) across
336 notes, populated by `scripts/backfill-connections.ts` on 2026-06-11. Going-forward
`process-llm.ts` writes new connections as notes are processed.

---

## Approach

`constellation.ts` already owns the Phase A helpers (`loadNoteClusters`, `buildParentFields`,
`exportClusterNotes`). Phase B adds a parallel pair:

- **`loadNoteFriends(db, topN=5)`** — queries `note_connections` bidirectionally (UNION
  source→target and target→source), joins `raw_notes` for title+created_at, groups by note,
  keeps top-5 by `similarity_score DESC`. Returns `Map<noteId, Array<{title, created_at}>>`.
  Raw note data (not wikilinks) to avoid a circular import: `obsidian-render.ts` imports
  `constellation.ts`, so `constellation.ts` must not import back.

- **`buildFriendFields(basenames: string[])`** — emits `friend:: [[basename]]` per line, same
  shape as `buildParentFields`.

`obsidian-render.ts` converts raw note data → wikilink basenames using its own `noteFilename`,
then passes `friendBasenames: string[]` into `renderNoteMarkdown` (new optional last param,
defaults to `[]` so all existing call sites are unchanged). The friend block is injected after
the `parent::` block, before the `## ✍️ Your note` section.

**Top-N = 5.** With an average of ~20 connections per note at ≥0.75 threshold, 5 keeps the
ExcaliBrain graph legible.

---

## Acceptance criteria

- [ ] Each exported note contains `friend:: [[basename]]` lines for its top-5 most-similar notes
- [ ] Connections are bidirectional (if A→B is in `note_connections`, B also lists A as a friend)
- [ ] Notes with no connections export cleanly with no friend block
- [ ] Existing export hash logic re-exports notes that gain friend edges on next run (hash covers
      the full rendered markdown including friend block)
- [ ] `npm test` green
- [ ] Guide updated: `docs/guides/features/knowledge-constellation.md`

---

## Out of scope

- Cluster→cluster `friend::` edges (clusters relate through note membership, not cosine similarity)
- Configurable top-N at runtime (5 is a constant; can be revisited once the vault feel is known)
- Phase 2 of note_connections (the 7-day floor in `process-llm.ts` that filters recent notes
  from going-forward connection detection — documented in the PR #57 body as a known follow-up
  for Act 1)
