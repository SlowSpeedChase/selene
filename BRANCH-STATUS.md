# Branch Status: feat/knowledge-constellation (Phase A)

**Created:** 2026-05-29
**Design Doc:** docs/plans/2026-05-29-knowledge-constellation-design.md
**Research:** docs/plans/2026-05-29-excalidraw-excalibrain-research.md
**Current Stage:** planning
**Last Rebased:** 2026-05-29 (branched fresh off main @ 028b058, includes clustering merge #52)

## Overview

**Phase A of the knowledge constellation:** teach `src/workflows/export-obsidian.ts` to emit
**Dataview relationship fields** into the notes (and cluster index notes) it exports, so the
**ExcaliBrain** plugin in Obsidian renders a navigable cluster→note hierarchy the user can "fly"
through. ExcaliBrain itself needs no code — it reads the structure Selene writes.

Concretely:
- Read existing `topic_clusters` (hierarchical, `parent_id`) + `topic_note_links` from the synthesis layer.
- For each exported note, emit `parent:: [[<cluster>]]` for the cluster(s) it belongs to.
- Export each cluster as a note carrying `parent:: [[<parent cluster>]]` to expose the hierarchy.

**Validated:** feel-test on real notes (dev vault + ExcaliBrain 0.2.17) — recenter-hop navigation
accepted as "flying." See design doc.

**NOT in this phase:** Phase B (note↔note `friend::` edges from `note_connections`) — gated on a
separate diagnostic spike into why `note_connections` is empty despite a wired write path.

## Dependencies

- **Synthesis layer (already merged, #52):** `topic_clusters` / `topic_note_links` populated in prod
  (`~/selene-data/selene.db`: 83 clusters / 286 links). Phase A reads these — no schema change.
- **ExcaliBrain + Dataview + Excalidraw** installed in the target Obsidian vault (dev vault already set up).
- None blocking.

---

## Stages

### Planning
- [x] Design doc exists and approved (Phase A scope)
- [x] Conflict check completed (rebased on main incl. clustering merge; reads synthesis tables read-only)
- [x] Dependencies identified and noted
- [x] Branch and worktree created
- [x] Implementation plan written (superpowers:writing-plans) → docs/plans/2026-05-29-knowledge-constellation-phase-a-plan.md

### Dev
- [ ] Tests written first (superpowers:test-driven-development)
- [ ] `export-obsidian.ts` reads `topic_clusters` / `topic_note_links`
- [ ] Emits `parent::` Dataview fields on notes + cluster index notes
- [ ] Cluster hierarchy (`parent_id`) exported as `parent::` chains
- [ ] No linting/type errors (no `ANY` type; parameterized SQL)
- [ ] Code follows project patterns

### Testing
- [ ] Unit tests pass
- [ ] Export run against a dev-DB copy produces expected `parent::` fields (test_run isolation)
- [ ] Open exported vault in ExcaliBrain → cluster→note hierarchy renders + is navigable
- [ ] Re-run export (simulate scheduled regen) → graph re-reads cleanly, no dupes/breakage
- [ ] Verified with superpowers:verification-before-completion

### Docs
- [ ] User-facing change → create `docs/guides/features/knowledge-constellation.md` + hub link
- [ ] Roadmap: move design doc toward Done in `docs/plans/INDEX.md`
- [ ] Code comments where the cluster→Dataview mapping is non-obvious

### Review
- [ ] Requested review (superpowers:requesting-code-review)
- [ ] Review feedback addressed
- [ ] Changes approved

### Ready
- [ ] Rebased on latest main
- [ ] Final test pass after rebase
- [ ] BRANCH-STATUS.md fully checked
- [ ] Ready for merge

---

## Notes

- **Which DB:** `config.ts:getDbPath()` → prod `~/selene-data/selene.db` (has the clusters). The repo
  `data/selene.db` is a STALE non-symlink copy — never query it.
- **Open Q (carry from design):** cluster/note filename resolution for `[[wikilinks]]` (existing note
  filenames carry dates/parens); ExcaliBrain performance ceiling at full note volume.
- **Phase A value over the demoed baseline:** the feel-test flew on body-text `[[wikilinks]]`. Phase A
  adds clean structured `parent::` hierarchy + multi-level cluster containers that flat body links can't express.

---

## Blocked Items

- None.
