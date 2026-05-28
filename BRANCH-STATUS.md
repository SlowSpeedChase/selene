# Branch Status: phase-X.Y/feature-name

**Created:** YYYY-MM-DD
**Design Doc:** docs/plans/YYYY-MM-DD-design.md
**Current Stage:** planning
**Last Rebased:** YYYY-MM-DD

## Overview

Brief description of what this branch implements.

## Dependencies

- List any dependencies on other branches or external factors
- None | Waiting on phase-X.Y | Requires [external thing]

---

## Stages

### Planning
- [ ] Design doc exists and approved
- [ ] Conflict check completed (no overlapping work)
- [ ] Dependencies identified and noted
- [ ] Branch and worktree created
- [ ] Implementation plan written (superpowers:writing-plans)

### Dev
- [ ] Tests written first (superpowers:test-driven-development)
- [ ] Core implementation complete
- [ ] All tests passing
- [ ] No linting/type errors
- [ ] Code follows project patterns

### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed
- [ ] Edge cases verified
- [ ] Verified with superpowers:verification-before-completion

### Docs
- [ ] workflow STATUS.md updated (if workflow changed)
- [ ] README updated (if interface changed)
- [ ] Roadmap docs updated
- [ ] Code comments where needed
- [ ] User-facing change? If yes: feature guide created/updated in `docs/guides/features/` + hub link added

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

Running notes, decisions, questions, etc.

---

## Blocked Items

Move any blocked checklist items here with reason:

- [ ] BLOCKED: [Item] - [Reason]

## Findings during execution

- **Task 1 finding (pre-existing, not introduced here):** `SELENE_ENV=test` is unreachable from the CLI. `src/lib/config.ts:10-11` loads `.env.development` with `override:true` whenever `SELENE_ENV !== 'production'`, and `.env.development` sets `SELENE_ENV=development` — clobbering a CLI `SELENE_ENV=test`. Impact: the `test` tier is dead; `development` and `production` work. Our prod/dev split is unaffected (prod uses `production` which skips the override; dev uses `development`). Do NOT build verification that relies on `SELENE_ENV=test` selecting `data-test/`. Fix is out of scope for this branch.

- **Task 8 (dev sandbox rebuild + dev config routing):** STOP-and-report outcome — did NOT build `scripts/refresh-dev-db.sh`. Evidence:
  - **Dev config routing VERIFIED correct.** `SELENE_ENV=development npx ts-node` resolves: `env=development`, `db=~/selene-data-dev/selene.db`, `vault=~/selene-data-dev/vault`, `digests=~/selene-data-dev/digests`, `appleNotes=false`, `trmnl=false`. Never touches real `~/selene-data/` or the iCloud vault.
  - **No scheduled DEV agents.** No `com.selene.dev.*` plists in `launchd/`; dev workflows are manual (`scripts/dev-process-batch.sh`). Correct per design.
  - **Dev vault is scratch.** `~/selene-data-dev/vault/Selene` — a local scratch dir, NOT the iCloud Obsidian vault (`~/Library/Mobile Documents/iCloud~md~obsidian/...`).
  - **Dev DB is FICTIONAL fixtures, not anonymized-real.** `~/selene-data-dev/selene.db` exists (541 notes, `_selene_metadata.environment=development`, created 2026-02-21). Real DB has only 293 notes. Titles are invented ("Centering practice", "Concert tonight"). Intended dev pattern = purpose-built schema + generated fictional data, NOT a copy of real data.
  - **Runtime guard makes copy-real-into-dev impossible by design.** `src/lib/db.ts:15-48` throws unless `_selene_metadata.environment='development'`. The real DB has NO `_selene_metadata` table, so a `.backup` of real→dev would fail the guard at startup. This is hard evidence the "anonymized copy of real data" framing is the stale part — code mandates the fictional-fixture pattern.
  - **Existing anonymizer is inadequate for journal content (PII-adequacy flag).** `src/lib/anonymize.ts` is regex-only (EMAIL/PHONE/URL/UUID) + optional Ollama NER (names/orgs). It does NOT scrub the *substance* of a personal ADHD journal (reflections, feelings, relationship/work/health context — the actually-sensitive part). Wrapping it in a refresh script would ship exactly the "weak scrubber" the task said to avoid.
  - **Schema divergence.** Real DB has ~45 tables (agent_*, meal_plans, recipes, projects, topic_clusters, note_facets, ...); `create-dev-db.sh` builds a bespoke ~20-table schema. Wholesale copy is off-design.
  - **REBUILDABILITY GAP (needs user decision).** `scripts/CLAUDE.md` documents `seed-dev-data.ts`, `reset-dev-data.sh`, `generate-dev-fixture.py` as existing, but NONE exist on disk (stale docs). So the 541-note dev DB cannot currently be regenerated. Recommendation: reconstruct the fictional-fixture generators (safe, zero PII risk, matches code intent) rather than invest in a genuine content-rewriting anonymization pipeline — but flagged for the user since originals are gone and it's a larger build than Task 8.
