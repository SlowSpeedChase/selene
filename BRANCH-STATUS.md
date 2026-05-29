# Branch Status: feat/content-multitopic-clustering

**Created:** 2026-05-29
**Design Doc:** docs/plans/2026-05-29-content-based-multitopic-clustering-design.md
**Current Stage:** review → ready (pending merge + prod rollout)
**Last Rebased:** 2026-05-29 (onto origin/main incl. PR #51 env-aware test_run guard)

## Overview

Fix the iPad Notes "E-Ink Empowerment" 104-note source bucket by deriving `topic_clusters`
from the controlled 8-category taxonomy instead of whole-note embeddings. Pivoted off the
original chunk/embedding plan after a Phase 0 spike failed the gate (homogeneous e-ink
journaling re-collapses no matter the unit). Notes link to **every** category they touch
(multi-membership via existing `topic_note_links`); a one-shot backfill classifies older
drafts; the embedding-clustering code is removed. No schema change.

## Dependencies

- Builds on PR #51 (env-aware `testRunFilter`) — already rebased in.
- Prod rollout (post-merge, human-run): `scripts/backfill-categories.ts` then
  `SELENE_REBUILD_CLUSTERS=1` rebuild against the real prod DB, then verify on the iPad.

---

## Stages

### Planning
- [x] Design doc exists and approved (pivoted to category-derived; user approved unify-on-categories)
- [x] Conflict check completed (rebased on PR #51; only non-overlapping files)
- [x] Dependencies identified and noted
- [x] Branch and worktree created
- [x] Implementation plan written (superpowers:writing-plans)

### Dev
- [x] Tests written first (TDD on `category-clusters.ts` — 16 tests)
- [x] Core implementation complete (helpers, backfill, synthesize-topics rewrite)
- [x] All tests passing (jest 5 suites / 37 tests)
- [x] No linting/type errors (`tsc --noEmit` clean)
- [x] Code follows project patterns (no `any`, parameterized SQL, env-aware test_run filter)

### Testing
- [x] Unit tests pass
- [x] Integration tests pass (end-to-end run on a prod COPY)
- [x] Manual testing completed (backfill + rebuild on `/tmp/selene-rebuild-test.db`)
- [x] Edge cases verified (multi-membership, empty-category deletion, orphan cleanup, NULL-category notes logged)
- [x] Verified with end-to-end validation (8 categories, 104 multi-membership, 282/286 covered)

### Docs
- [x] workflow STATUS — n/a (no per-workflow STATUS files in this repo)
- [x] README/interface — n/a
- [x] Roadmap docs updated (design doc → Done + validation results; INDEX.md moved to Done)
- [x] Code comments where needed
- [x] User-facing change → guide updated: `docs/guides/features/synthesis-layer.md` rewritten + `note-annotation.md` updated; both already linked in `docs/USER-EXPERIENCE.md`

### Review
- [x] Spec-compliance review per task (subagent-driven-development)
- [x] Domain review: `synthesis-reviewer` on the synthesize-topics rewrite; findings fixed
- [x] Changes approved (review fixes committed: stale-empty-category, num_ctx, normalization)

### Ready
- [x] Rebased on latest main
- [x] Final test pass after rebase
- [x] BRANCH-STATUS.md fully checked
- [ ] Ready for merge — **awaiting user go-ahead to open PR**

---

## Notes

- Pivot recorded in the design doc's "What we learned" + "Spike RESULTS" sections.
- Validation was on a prod **copy** (`SELENE_DB_PATH=/tmp/...`, `SELENE_ENV=production`) — the
  live prod DB was never written to.

## Known follow-ups (non-blocking, in design doc)

- 4 `NULL`-category notes after backfill (re-run backfill or classify manually).
- Dead `is_proto = 1` "Pattern forming" path in `synthesis-digest.ts` (proto-clusters retired) — remove later.
- `process-llm.ts` writes `category` unvalidated (root cause of messy values; read-side normalization covers it for now).
