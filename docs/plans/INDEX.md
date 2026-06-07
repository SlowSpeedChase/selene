# Design Documents Index

**Last Updated:** 2026-05-31

Design docs are the planning unit for Selene development. Each doc captures an idea, architecture, and implementation plan.

---

## Status Definitions

| Status | Meaning | Next Step |
|--------|---------|-----------|
| **Vision** | Idea captured, needs refinement | Add acceptance criteria, ADHD check, scope check |
| **Ready** | Implementation-ready | Create branch, start GitOps workflow |
| **In Progress** | Branch exists, being built | Complete GitOps stages |
| **Done** | Implemented and merged | Archive if old |

**A design is "Ready" when it has:**
- [ ] Acceptance criteria defined
- [ ] ADHD check passed (reduces friction? visible? externalizes cognition?)
- [ ] Scope check passed (< 1 week of focused work)
- [ ] No blockers

**Before moving a design to "Done":** Did this add or change something you interact with?
- **Yes** → create or update the matching guide in `docs/guides/features/` and add/update its link in the hub (`docs/USER-EXPERIENCE.md`).
- **No** (invisible refactor/infra) → note "no user-facing change" and move on.

---

## Vision (Needs Refinement)

Ideas captured but not yet ready for implementation.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|
| 2026-06-07 | [2026-06-07-executive-assistant-wants-design.md](2026-06-07-executive-assistant-wants-design.md) | executive-function, wants, coalescence, habit, eventkit | **Selene as executive assistant — coalescing fractured notes into "wants."** Three roles over one note graph: **librarian** (organize — ~done), **archivist** (preserve + resurface — half-built; `facts.db` is the vault), **executive assistant** (act — the gap). Built in **two acts**. **Act 0 (near-term, habit-first):** a tiny daily *gift* grafted onto the existing worksheet — buried-treasure rediscovery + connection + a capture box + four guilt-free taps (important/keep/not now/let go); every tap silently logs an **attention signal** that becomes your "top X" (`salience = engagement + recency, decayed`). Framing is load-bearing ("things I noticed for you," never "review queue"); delight-first, ≤3 items, ~30s; reuses shipped infra (only new piece = an attention-log table). **Act 1 (the dream):** fragments **coalesce** into named wants via the note relationship graph (1-to-few matching, *not* the embedding-clustering that died on the e-ink bucket); assistant proposes a forming want → you bless; cloud LLM plans on **anonymized** input (per-stage model split: local detection, cloud planning); settled steps hand off to Apple Reminders/Calendar via a native **EventKit** Swift CLI (`selene-reminders`, mirrors `selene-calendar`), **ID-keyed bidirectional**, Lumen-native; wants resurface only on a *positive* signal (new fragment / external ripeness) — **no nagging**, decay = graceful dormancy. The reaction verbs do double duty (Act 0 attention signals → Act 1 want-lifecycle controls); the ritual never changes as the UI grows. **Build principle:** maximal reuse (community detection for knots, HN-style decay for ranking, Claude API for planning, EventKit for tasks). **Parallel tracks:** revive the empty `note_connections` (load-bearing; same spike as Constellation Phase B), + a periodic **collaborator-scout** agent (prior-art/library scan). **Supersedes** `close-the-loop` + `interactive-worksheets` Ph2+. Next step: refine, then promote **Act 0** to Ready + writing-plans. |
| 2026-05-26 | [2026-05-26-interactive-worksheets-design.md](2026-05-26-interactive-worksheets-design.md) | ipad, pencilkit, ocr, review-ritual | Handwritten iPad worksheets Selene generates from your notes; each answer routes back as an action (archive / follow-up / new note). v1 = daily review ritual. On-device OCR, M-series iPadOS 17+ (1st-gen Pro out). Builds on folio's unbuilt markup app; app talks directly to Selene. Phased: Ph0 freeform warm-up → Ph1 structured review → Ph2+ generators. **Reality-check (2026-05-29): Ph0 + Ph1 SHIPPED (2026-05-27, routes live on prod :5678). Only Ph2+ generators remain — still Vision because they need design decisions first (generator location, schedule cadence, weekly-vs-daily) before acceptance criteria can be written.** |
| 2026-04-12 | [2026-04-12-model-audit-design.md](2026-04-12-model-audit-design.md) | llm, benchmarking, ollama | Per-stage model audit (curiosity-driven). Approach B locked; paused mid-design on fixture strategy. **Note (2026-05-29): the fixture blocker is dischargeable by the dev showcase corpus (boundary item A) — once that exists it doubles as the audit fixture. Off the critical path; resume when curious.** |
| 2026-03-21 | [2026-03-21-close-the-loop-design.md](2026-03-21-close-the-loop-design.md) | executive-function, things | Thread/task completion feedback ideas still valid; implementation references archived systems (threads, extract-tasks, BriefingViewModel). Needs redesign against agent-layer architecture. |
| 2026-02-13 | 2026-02-13-database-architecture-evaluation.md | architecture, infra | Decision record: keep LanceDB + SQLite, skip graph DB. Resolved — kept for reference. |

---

## Ready (Implementation-Ready)

These have acceptance criteria, ADHD check, and scope check. Ready to create a branch.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|
| 2026-06-01 | [2026-06-01-fact-store-rebuild-design.md](2026-06-01-fact-store-rebuild-design.md) | architecture, regeneration, sqlite, ops | **✅ Phase 2 `rebuild` MERGED to `main`** (origin/main `2512c99`); Phase 3 (`category_overrides`) remains. All 10 tasks done; gate green — tsc clean, jest 30/30+191/191, `verify-rebuild.sh` 20/20 across 5 scenarios. The `prod-agents.sh` extraction is proven a **pure move** (5 cutover-reachable functions byte-identical to `origin/main`); `verify-cutover.sh` is dark from pre-existing fixture-rot (dev DB migrated to two-file) — relight tracked as a follow-up in the plan. **Fact-store Phase 2 — the `rebuild` command.** Now that Ph1's two-file split is LIVE in prod, this is the command that makes `selene.db` actually disposable: wipe it (**truncate the derived tables — NOT a file delete**, because `processed_notes`/`note_embeddings` have no runtime CREATE-IF-NOT-EXISTS; verified empirically), re-derive the whole corpus from `facts.db` (process-llm → distill → synthesize → export), validate, keep-or-rollback. Serves all three drivers equally (reprocess-on-upgrade / disaster recovery / safe experimentation). **Approach B (chosen):** typed, jest-tested TS core (`scripts/rebuild.ts` + pure `src/lib/rebuild-core.ts`) owns all logic; bash confined to `launchctl` via a NEW shared `scripts/lib/prod-agents.sh` **extracted** from `cutover-prod.sh` (regression net = `verify-cutover.sh` stays 45/45). **Dev-first, prod-capable** (Claude builds/tests on /tmp + dev `.backup`, never runs vs prod; operator runs the prod path). **Whole-corpus only**, **through Obsidian export**. Safety: verified backup of `selene.db` (facts.db never touched — precious/TM-backed), **auto-rollback** on a failed gate; on prod the **webhook server stays UP** (capture writes only facts.db → zero capture outage; only derivation agents stop) with an EXIT trap restarting agents on any exit. Gate = pure `verdict(PRE,POST,thresholds)`: **≥95% coverage floor** + **≤20% downward drift** per metric, both env-overridable, zero-baseline drift skipped. Crash-between-wipe-and-validate is self-healing (pending remainder finished by the live pipeline). `--dry-run` + `SIMULATE_*` hooks prove both rollback paths; `verify-rebuild.sh` is the e2e harness. Human layer (`review_state`) survives automatically (lives in facts.db) — explicit re-apply + `category_overrides` are **Phase 3**. Guide → `releases.md`. Plan: [2026-06-01-fact-store-rebuild-plan.md](2026-06-01-fact-store-rebuild-plan.md) (10 TDD tasks). Branch `feat/fact-store`. |
| 2026-05-31 | [2026-05-31-fact-store-design.md](2026-05-31-fact-store-design.md) | architecture, data-integrity, regeneration, sqlite | **✅ DONE 2026-06-01: Ph1 LIVE IN PROD (merged to `main`).** Cutover executed via `./scripts/cutover-prod.sh --ref origin/main` — 295 notes migrated to `facts.db`+`selene.db`, prod healthy (`status:ok`). Two prior attempts AUTO-ROLLED-BACK cleanly (zero data risk) on real prod-data cruft the clean dev DB couldn't surface (6 orphaned `processed_notes` + 61 pre-existing FK violations); the migration was hardened to TOLERATE pre-existing referential cruft — a faithful id-preserving migration preserves it (`post==pre` for orphan/self-ref asserts, `post<=pre` for `foreign_key_check`), failing only on what it INTRODUCES. The build's e2e caught + fixed an earlier ship-blocker (`ALTER RENAME` repoints child FKs → stripped `raw_notes` FK from `processed_notes`/`note_embeddings`). High-effort code review (9 findings) resolved; dev-tooling caught up (`reset-dev-data.sh` migrates-before-seeding, `cleanup-tests.sh` two-file-aware); **dev→prod vault-path bug FIXED** (`resolveVaultPath`: dev vault is always the sandbox, `/tmp` the only honored override). LESSON: validate the migration on a `.backup` copy of REAL prod BEFORE merging — the dev DB cannot surface prod's historical cruft. Ph2 (`rebuild`) + Ph3 (`category_overrides`) remain.** — **Ingest-only fact store + regenerable derived DB.** Split the single DB into **two files**: `facts.db` (PRECIOUS — `captured_notes` append-only + human `category_overrides`/`review_state`, Time-Machine-backed) and `selene.db` (DISPOSABLE — all LLM/derived + pipeline bookkeeping, read-through `ATTACH`). "Separate by durability, not source": the file boundary *is* the provenance flag. Rebuild = wipe `selene.db` → re-derive from facts → re-apply human layer last (keyed on `source_uuid` + category **slug**, never churning surrogate ids — verified safe: `pkm_review_state` keys on note id, clusters key on slug). "Pending" becomes derivation-absence (the lone `db.ts:77` status query). **Re-derives, does not restore** (LLM non-deterministic). Phased: **Ph1 the split** (<1wk, Ready) → Ph2 `rebuild` cmd + validation → Ph3 override *feature* (net-new). Does NOT fix the orthogonal dev→prod vault-path bug. Plan: [2026-05-31-fact-store-plan.md](2026-05-31-fact-store-plan.md) (Ph1, 10 TDD tasks, `raw_notes`-view compat strategy). Branch `feat/fact-store`. |
| 2026-05-31 | [2026-05-31-fact-store-cutover-design.md](2026-05-31-fact-store-cutover-design.md) | ops, migration, prod, deploy | **✅ DONE 2026-06-01 — executed against prod; fact store LIVE.** The prod cutover runbook for the fact-store split (the gate before merging Phase 1). **Hybrid:** (A) an `ensure-migrated` guard in `db.ts` startup — dev/clone **auto-migrates** (self-heal), prod **fails loud** if un-migrated (can never silently run the incoherent split); (B) `scripts/cutover-prod.sh`, one operator-run orchestrator: pre-flight build-gate → pause watcher → stop `com.selene.prod.*` → **verified backup** → `migrate-to-fact-store.ts` → **Gate 1** (content-free inspect + capture→pending probe) → `deploy-prod.sh` → restart → **Gate 2** (live /health + probe) → resume watcher, with **auto-rollback** to byte-for-byte single-file on either gate. Brief downtime window is inherent (old code can't read a migrated DB; new code can't safely read an un-migrated one). Claude writes + /tmp-tests it but **never runs it against prod** (prod-data guard) → every check content-free by construction. Plan: [2026-05-31-fact-store-cutover-plan.md](2026-05-31-fact-store-cutover-plan.md) (6 TDD tasks). Branch `feat/fact-store`. |
| 2026-05-29 | [2026-05-29-remote-ipad-development-design.md](2026-05-29-remote-ipad-development-design.md) | ipad, tailscale, dev-environment, travel | Develop SeleneMarkup remotely while traveling. MacBook Air + iPad = self-contained build/deploy station (`./redeploy.sh --dev`); Mac mini stays home as server, reached over Tailscale (`100.111.6.10`). Persistent dev-mode server on :5679 (prod-seeded dev DB, writes isolated from prod) via a new `com.selene.dev.server` launchd agent. Only code change: `AppConfig` `#if SELENE_DEV` IP. Pre-trip checklist (GitHub remote, laptop signing, prod→dev snapshot, sleep-disable, cellular pre-flight test). **Trip-prioritized (2026-05-29): the at-home/USB setup phases must finish before departure; only the away verification happens on the trip. Independent of the foundation work — runs in parallel.** |
| 2026-04-12 | [2026-04-12-pkm-browse-layer-design.md](2026-04-12-pkm-browse-layer-design.md) | pkm, browse, ipad | LAN web dashboard (`/pkm/*`) + review state + slim exporter upgrade. 4 tracks, ~1 week. **Promoted Vision → Ready 2026-05-29** (design already has acceptance criteria + ADHD + scope checks; no design blockers). Prerequisite: the category backfill — the *same* `scripts/backfill-categories.ts` run as the content-clustering prod rollout, so that rollout unblocks this too. ⚠️ Track 3 edits `export-obsidian.ts`, shared with Knowledge Constellation Phase A — build the two in sequence and make the content-hash churn-guard cover the full rendered output (body + frontmatter + Dataview fields) so it can't freeze the `parent::` edges. **Update (2026-05-30): Tracks 0–2 SHIPPED + deployed.** Category backfill (rollout) done; review-state layer (`pkm-db.ts`) + the `/pkm/*` LAN dashboard (`pkm-queries`/`pkm-render`/`routes/pkm.ts`, LAN-only, 230 tests, HTTP-smoke-verified) live on :5678. Guide: `docs/guides/features/pkm-browse.md`. Track 3 (exporter slim upgrade — mind the content-hash guard above) remains. |
---

## In Progress

Branch exists, actively being worked on.

| Date | Document | Branch | Notes |
|------|----------|--------|-------|
| 2026-06-06 | [2026-06-06-maintainability-cleanup.md](2026-06-06-maintainability-cleanup.md) | `chore/maintainability-cleanup` | **Code/glue maintainability cleanup** (src/ + scripts/ only; docs untouched). ~1,453 lines of low-risk removal across 12 ranked tasks, deletions-first: dead subsystems left behind by the 2026-03-21 simplification (db.ts thread/chat/memory, ContextBuilder, self-referential orphans, bit-rotted scripts + dead package.json entries), two drift fixes (.env.example, launchd install list silently skipping folio-feedback), and six low-risk consolidations. Produced by an 8-finder review + skeptical verification; 4 over-abstraction candidates explicitly rejected. Fact-store cutover machinery never deleted (tasks 11–12 de-dup *within* it). Executed via subagent-driven development. |
| 2026-05-29 | [2026-05-29-knowledge-constellation-design.md](2026-05-29-knowledge-constellation-design.md) | `feat/knowledge-constellation` | **Phase A** (data-ready): teach `export-obsidian.ts` to emit `parent::` Dataview fields from existing `topic_clusters`/`topic_note_links` so ExcaliBrain renders a cluster→note hierarchy you fly through in Obsidian. Validated by feel-test on real notes. Phase B (note↔note `friend::` edges) gated on a diagnostic spike into why `note_connections` is empty. Research: [2026-05-29-excalidraw-excalibrain-research.md](2026-05-29-excalidraw-excalibrain-research.md). **Update (2026-05-30): Phase A SHIPPED + deployed.** `export-obsidian.ts` now emits `parent:: [[cluster]]` + writes `Constellation/<cluster>.md` index notes (`src/lib/constellation.ts`, 12 tests); merged to main, the hourly prod export auto-populates the iCloud vault. Visual ExcaliBrain render check is the one remaining (operator-only) gate. Phase B (`friend::` edges) still gated on the `note_connections` spike. |

---

## Done (Implemented)

| Date | Document | Completed | Notes |
|------|----------|-----------|-------|
| 2026-05-31 | [2026-05-31-sub-categories-design.md](2026-05-31-sub-categories-design.md) | 2026-06-06 | **Phase 1 DONE** (branch `feat/sub-categories`). A second taxonomy level under the fixed 8 categories — facets like *Running* under *Health & Body*. **Seed taxonomy is a git-tracked config** the user edits to curate: `src/config/sub-taxonomy.ts` (git *is* the precious layer — a fact-store `rebuild` can't wipe it; no `facts.db` change). `process-llm.ts` makes a *closed-set* sub-category choice per category a note landed in, stored as a per-category JSON map in `processed_notes.sub_categories` (NULL = retriable Ollama failure, `{}` = known-empty). `synthesize-topics.ts` `materializeSubClusters` upserts sub-cluster `topic_clusters` rows with `parent_id` + namespaced slug (`health-body/running`) + note→sub-cluster links; the orphan-cleanup guard (`isValidClusterSlug`) treats `<categorySlug>/<sub>` as valid (the landmine — covered by a regression test). `constellation.ts` emits `parent::` edges so ExcaliBrain renders category → sub-cluster → note (export join was already future-proofed). One-shot `scripts/backfill-sub-categories.ts` (`--report` = content-free per-category histogram with `none`/misfit %, `--dry-run`); `selene-inspect coverage` adds `subCategoryCoverage`. iPad `/api/clusters` browse stays **top-level** (sub-clusters excluded) in Ph1. **Measure-and-iterate loop:** edit the config → re-run backfill → read `none%` (after the backfill drains NULLs) → adjust → repeat; `none` misfits are deliberate Phase 2 raw material. **Phase 2 REMAINS** (emergent tail mining the `none` residual → soft sub-cats + firmness gradient + curator-agent autonomy + firm taxonomy promoted to a precious `facts.db` table). Plan: [2026-06-06-sub-categories-plan.md](2026-06-06-sub-categories-plan.md). Guides: `synthesis-layer.md`, `knowledge-constellation.md`. |
| 2026-05-31 | [2026-05-31-living-system-map-design.md](2026-05-31-living-system-map-design.md) | 2026-05-31 | **Living system map shipped.** Generated, drift-proof workflow inventory at `docs/SYSTEM-MAP.md` — a 3-level zoom ladder (CLAUDE.md pointers → SYSTEM-MAP.md → block-diagrams + code). `scripts/gen-system-map.ts` reads `src/workflows/*.ts` + `launchd/*.plist`, harvests `// @map` comments, injects the table between `<!-- GENERATED -->` markers (hand-written prose preserved). Caught + fixed real drift: CLAUDE.md said **6** workflows, the truth is **12**; also caught `export-obsidian`'s `Minute`-only plist being mis-rendered as `daily 00:00` instead of `hourly` (launchd cron-wildcard semantics). Stop-hook `--check` flags drift on workflow/plist changes (verified fires+clears). Logic in `src/lib/system-map.ts` (15 jest tests). De-drifted CLAUDE.md (counts→pointers + nav row) + block-diagrams (inventory-of-record pointer). Two-stage reviewed (spec ✅, quality ✅ after pipe-escape + precedence fixes). Plan: [2026-05-31-living-system-map-plan.md](2026-05-31-living-system-map-plan.md). Guide: `docs/guides/features/system-map.md`. Branch `feature/living-system-map`. |
| 2026-05-29 | [2026-05-29-dev-prod-boundary-hardening-design.md](2026-05-29-dev-prod-boundary-hardening-design.md) | 2026-05-31 | Made the two-tier dev/prod split *trustworthy*. **B (guard):** LIVE — `prod-data-guard.sh` (PreToolUse Bash hook) + `permissions.deny` block real-note reads; `selene-inspect` is the sanctioned content-free prod read; `SELENE_GUARD_OFF=1` overrides. **A (corpus):** designed showcase corpus (3 threads + multi-topic monster + near-dup pair + length extremes + 8 category anchors) merged `24d6a00`. **A5 validation gate run 2026-05-31** surfaced + fixed two latent bugs that had silently broken the dev gate since the 2026-03-21 simplification (masked in prod, fatal on a fresh DB): (1) `dev-process-batch.sh` drove 5 *archived* workflows + skipped the current core steps → rewrote to drive `process-llm→distill-essences→synthesize-topics→export-obsidian` (`--all` drain w/ no-progress break, schema-tolerant `--status`, 15-check contract test); (2) `essence`/`essence_at` were created only by `export-obsidian` (runs last) → moved column ownership to producer `distill-essences.ensureEssenceColumns()`. A third bug (in the rewrite itself) was caught only by running `--all` end-to-end — the distill drain skipped on a fresh DB because it counted the not-yet-created `essence` column → fixed drain() to run-at-least-once. **A5 results** — two runs: *corpus behavior* (fresh reset → 90 notes via direct workflow calls, 0 errors) = 8/8 categories, threads cluster (Lighthouse 12/12→Projects&Tech, Half-marathon 10/10→Health&Body), **monster note → 5-cluster multi-membership** (eink-mega-bucket pathology behaves as designed), 90/90 essenced; *script `--all` path* (fresh reset → 43-note core via `./scripts/dev-process-batch.sh --all`) drained to pending 0, 43/43 essenced, 8 clusters, terminated cleanly. Branch `fix/dev-process-batch` (tests: jest 86/86, 15-check contract, drain unit test, distill migration test; tsc clean). Operator-only check remaining: eyeball dev vault. No end-user-facing change. |
| 2026-05-30 | [2026-05-30-idempotent-obsidian-reexport-design.md](2026-05-30-idempotent-obsidian-reexport-design.md) | 2026-05-30 | **Fixed the `exported_to_obsidian` write-once gate** that left Constellation Phase A's `parent::` edges on only the ~40 notes exported after Phase A shipped. Replaced the boolean gate with a **rendered-output content hash** (`src/lib/obsidian-render.ts` — pure render + SHA-256 + DI'd reconcile loop, in-memory tested; `export-obsidian.ts` now a thin caller) → idempotent + self-healing export; first run backfills `parent::` to the whole corpus. Folded in PKM Track 3's exporter churn-guard. Code-reviewed; review caught a deleted-file self-heal gap (skip keyed on DB hash only) → fixed with an `existsSync` gate + regression test. 86/86 tests, tsc clean; integration-verified vs dev DB (run 1 wrote 140 / 130 with `parent::`, run 2 wrote 0 / skipped 140). Branch `feat/idempotent-obsidian-reexport`, merged to main `f185580`. Guides: `obsidian-library.md`, `knowledge-constellation.md`. **Known follow-up (deferred):** note-filename collisions (would re-path the whole vault). **Deploy:** reaches prod once main is pushed — the deploy-watcher then backfills the ~254 orphaned notes over ≤2 hourly runs, closing PKM Track 3 and unblocking the Constellation operator visual check. |
| 2026-05-29 | [2026-05-29-content-based-multitopic-clustering-design.md](2026-05-29-content-based-multitopic-clustering-design.md) | 2026-05-29 | Fixed the iPad Notes "E-Ink Empowerment" 104-note source bucket. **Pivoted** off the original chunk/embedding plan — a Phase 0 spike proved embedding clustering re-collapses on homogeneous e-ink journaling. Instead, `synthesize-topics.ts` now derives `topic_clusters` from the controlled 8-category taxonomy already on each note (`processed_notes.category` + `cross_ref_categories`), one row per non-empty category, names from the fixed list (no LLM naming → no source buckets), notes linked to **every** category they touch (multi-membership). One-shot `scripts/backfill-categories.ts` classifies ~148 older drafts; embedding-clustering code removed (net −code). No schema change. Validated on a prod copy: 8 content categories, 104 multi-membership notes, 282/286 covered. Branch `feat/content-multitopic-clustering`. Guide: `docs/guides/features/synthesis-layer.md`. **Prod rollout COMPLETE 2026-05-30:** prod now shows 8 content categories, multi-membership (avg 1.67 clusters/note), 13-note uncategorized tail (retryable). The nightly `synthesize-topics` crash that had silently blocked it (SQLITE_BUSY — `db.ts` had no `busy_timeout`) is fixed + deployed. Unblocked the prod value of Constellation A + PKM Browse. |
| 2026-05-28 | [2026-05-28-prod-dev-split-design.md](2026-05-28-prod-dev-split-design.md) | 2026-05-29 | Release boundary SHIPPED & cut over to production (PR #45). `~/selene` = dev sandbox (dev DB, ts-node, :5679, NO scheduled agents); `~/selene-build` = scratch build clone; `~/selene-prod` = prod (compiled `dist/`, real DB, iCloud vault, :5678, 11 `com.selene.prod.*` agents + deploy-watcher). Merge to main auto-deploys via a gated launchd watcher (build-gate, `.env` preserved, rollback archive, notifications). Two iPad targets built in `~/SeleneMarkup` (`feat/dev-prod-apps`). Dev data = fictional fixtures. Guide: `docs/guides/features/releases.md`. |
| 2026-05-26 | [2026-05-26-selene-mobile-companion-design.md](2026-05-26-selene-mobile-companion-design.md) | 2026-05-28 | iPad note annotation shipped: Notes tab in SeleneMarkup (cluster browse → note → PencilKit canvas → Vision OCR → new linked note). selene: `source_note_id` column + `src/routes/notes.ts` (4 endpoints, 4 jest tests). SeleneMarkup: NoteModels, AnnotationService (5 tests), 4 views, tab wiring, AppConfig.mainBaseURL. User guide at docs/guides/features/note-annotation.md. |
| 2026-05-26 | [2026-05-26-synthesis-retrieval-agent-design.md](2026-05-26-synthesis-retrieval-agent-design.md) | 2026-05-28 | Layered synthesis shipped: synthesize-topics.ts (nightly clustering + evolution detection), connection detection in process-llm.ts, 4 new digest sections, launchd agent at 2am. 17 tests. User guide at docs/guides/features/synthesis-layer.md. |
| 2026-05-26 | [2026-05-26-folio-kindle-agent-design.md](2026-05-26-folio-kindle-agent-design.md) | 2026-05-27 | Folio MCP server (4 tools): list_changed_documents, read_document, get_delivery_history, send_kindle_digest. Delta PDF delivery to Kindle. Registered in selene/.mcp.json. |
| 2026-05-27 | [2026-05-26-phase1-worksheets-related-notes-design.md](2026-05-26-phase1-worksheets-related-notes-design.md) | 2026-05-27 | Multi-field worksheets (free_capture + note_review) + "Selene remembers" panel. OCR review-before-submit step added. Track A (TypeScript) + Track B (Swift/iPad). User guide at docs/guides/features/interactive-worksheets.md. |
| 2026-05-25 | [2026-05-25-user-guides-design.md](2026-05-25-user-guides-design.md) | 2026-05-25 | Consolidated hub (USER-EXPERIENCE.md) + 5 per-capability feature guides in docs/guides/features/ from shared template. Wrap-up trigger via Done criteria + GitOps docs-stage checkbox. |
| 2026-05-25 | [2026-05-25-folio-ipad-delivery-design.md](2026-05-25-folio-ipad-delivery-design.md) | 2026-05-25 | send-ipad.ts: qrcode-terminal QR code → iPad opens folio LAN reader → Apple Pencil annotation → feedback back to Selene. |
| 2026-05-25 | [2026-03-21-eink-notebook-ingestion-design.md](2026-03-21-eink-notebook-ingestion-design.md) | 2026-05-25 | minicpm-v OCR, pdftoppm conversion, manifest tracking, WatchPaths launchd agent. Fixed npx path bug (exit 126). Direct ingest (no Drafts step). |
| 2026-05-24 | [2026-05-23-agent-layer-design.md](2026-05-23-agent-layer-design.md) | 2026-05-24 | Agent layer v1: 4 SQLite tables, BaseAgent + Things enricher, ActionExecutor, dashboard (4 views), Apple Notes + Obsidian delivery, launchd schedule at 9am/6pm |
| 2026-02-22 | 2026-02-22-claude-code-automations-design.md | 2026-05-24 | context7 + sqlite-dev MCP servers, TypeScript type-check hook, .env block hook, run-workflow + launchd-check skills. All implemented, plus extras (playwright MCP, db-query, workflow-health). |
| 2026-03-21 | 2026-03-21-codebase-simplification-design.md | 2026-03-21 | Strip to clean core — 20K→3.5K lines. SeleneChat, SeleneMobile, threads, 11 workflows archived. |
| 2026-03-21 | 2026-03-21-obsidian-librarian-design.md | 2026-03-21 | LLM-curated notes + topic indexes implemented in export-obsidian.ts |
| 2026-03-21 | 2026-03-21-obsidian-moc-design.md | 2026-03-21 | 8-category MOCs + code-generated Dashboard.md implemented in export-obsidian.ts |
| 2026-03-21 | 2026-02-22-voice-memo-llm-title-design.md | 2026-03-21 | Already implemented in transcribe-voice-memos.ts, moved from Ready |
| 2026-03-21 | 2026-02-19-calendar-context-linking-design.md | 2026-03-21 | Full chain: Swift CLI + ingestion + SeleneChat/Mobile UI + AI context, moved from Ready |
| 2026-02-14 | 2026-02-13-selene-mobile-ios-design.md | 2026-02-14 | Full parity iOS app, Tailscale networking, push + live activities, moved from Ready |
| 2026-03-18 | 2026-03-18-physical-digital-bridge-design.md | 2026-03-18 | Claude Vision whiteboard capture, daily planning sheet PDF, annotation closed loop |
| 2026-03-01 | 2026-03-01-remove-n8n-naming-design.md | 2026-03-01 | Rename selene-n8n to selene across 108 files, 665 tests passing |
| 2026-02-28 | 2026-02-28-thread-context-isolation-design.md | 2026-03-01 | Remove global fallback, thread-scoped memories, active project default, golden walkthrough (665 tests) |
| 2026-02-24 | 2026-02-24-selene-intelligence-upgrade-design.md | 2026-02-27 | Layers 1+2: ContextualRetriever, zen prompt rewrite, 53 planning patterns, 743 tests |
| 2026-02-21 | 2026-02-21-tiered-context-compression-design.md | 2026-02-22 | ContextBuilder, 3 new workflows, tier evaluation, essence backfill, health endpoint |
| 2026-02-21 | 2026-02-21-dev-environment-isolation-design.md | 2026-02-22 | Overmind + Procfile.dev, 536 seed notes, vault export fix, all 9 acceptance criteria pass |
| 2026-02-14 | 2026-02-14-context-blocks-apple-intelligence-design.md | 2026-02-14 | Chunk-based retrieval, Apple Intelligence LLM, LLM Router, background chunking pipeline |
| 2026-02-12 | 2026-02-12-menu-bar-orchestrator-design.md | 2026-02-13 | Menu bar app with Silver Crystal icon + workflow orchestration |
| 2026-02-12 | 2026-02-12-voice-memo-transcription-design.md | 2026-02-13 | Whisper.cpp transcription + Selene pipeline integration |
| 2026-02-12 | 2026-02-12-apple-notes-daily-digest-design.md | 2026-02-13 | Replace iMessage digest with pinned Apple Notes daily note |
| 2026-02-06 | 2026-02-06-thread-workspace-design.md | 2026-02-13 | Thread workspace: all 3 phases complete (context, actions, feedback loop) |
| 2026-02-13 | 2026-02-13-thread-workspace-phase3-design.md | 2026-02-13 | Feedback loop: on-demand Things sync, momentum boost, LLM "what's next" |
| 2026-02-13 | 2026-02-13-morning-briefing-redesign.md | 2026-02-13 | Structured cards, deep context chat, cross-thread connections |
| 2026-02-13 | 2026-02-13-thread-lifecycle-design.md | 2026-02-13 | Auto archive, split, merge threads — full lifecycle |
| 2026-02-06 | 2026-02-06-test-environment-isolation-design.md | 2026-02-06 | Complete test isolation with anonymized data |
| 2026-02-06 | 2026-02-06-memory-embedding-retrieval-design.md | 2026-02-06 | Embedding-based memory retrieval and consolidation |
| 2026-01-26 | today-view-design.md | 2026-01-26 | ADHD landing page with new captures and heating threads |
| 2026-02-05 | 2026-02-05-voice-input-design.md | 2026-02-05 | Voice input Phase 1: Apple Speech, push-to-talk, URL scheme |
| 2026-02-05 | 2026-02-05-selene-thinking-partner-design.md | 2026-02-05 | Proactive briefing, cross-thread synthesis, deep-dive dialogue |
| 2026-05-17 | 2026-02-13-trmnl-daily-digest-design.md | 2026-05-17 | Push morning digest to TRMNL e-ink display at 6am |
| 2026-02-02 | 2026-02-02-imessage-daily-digest-design.md | 2026-02-02 | iMessage daily digest at 6am via AppleScript |
| 2026-01-27 | 2026-01-27-selenechat-vector-search-design.md | 2026-01-27 | SeleneChat vector search integration |
| 2026-01-26 | 2026-01-26-lancedb-transition.md | 2026-01-27 | LanceDB vector DB, typed relationships |
| 2026-01-11 | selenechat-thread-queries-design.md | 2026-01-11 | Thread queries in SeleneChat |
| 2026-01-11 | obsidian-thread-export-design.md | 2026-01-11 | Thread export to Obsidian |
| 2026-01-10 | phase-3-living-system-design.md | 2026-01-11 | Thread reconsolidation |
| 2026-01-09 | n8n-replacement-design.md | 2026-01-10 | TypeScript backend |
| 2026-01-06 | test-isolation-design.md | 2026-01-06 | Test data isolation |
| 2026-01-05 | batch-embed-notes-design.md | 2026-01-05 | Batch embedding |
| 2026-01-05 | association-computation-design.md | 2026-01-06 | Note associations |
| 2026-01-04 | selene-thread-system-design.md | 2026-01-11 | Core thread system |
| 2026-01-04 | embedding-workflow-implementation.md | 2026-01-05 | Embedding workflow |

---

## Archived

Superseded, abandoned, or very old designs. Kept for reference.

<details>
<summary>View Archived (50+)</summary>

| Date | Document | Reason |
|------|----------|--------|
| 2026-05-24 | 2026-05-24-synthesis-layer-design.md | Superseded by 2026-05-26-synthesis-retrieval-agent-design.md — original used string-frequency clustering and Obsidian-only output; new design uses embedding clustering + retrieval agent + web UI. |
| 2026-02-15 | 2026-02-15-thinking-partner-upgrade-design.md | SeleneChat archived 2026-03-21. Core idea (proactive AI briefing) re-emerges in agent-layer. |
| 2026-02-13 | 2026-02-13-kitchenos-selene-integration-design.md | SeleneChat archived 2026-03-21. Conversational meal planning was the shell. |
| 2026-02-13 | 2026-02-13-voice-conversation-design.md | SeleneChat (Voice Phase 2 TTS) archived 2026-03-21. |
| 2026-02-04 | 2026-02-04-conversation-memory-design.md | SeleneChat archived 2026-03-21. mem0-style memory extraction idea preserved in design doc. |
| 2026-01-26 | selenechat-contextual-evolution.md | SeleneChat archived 2026-03-21. |
| 2026-01-26 | phase-7.3-cloud-ai-integration.md | Assumed SeleneChat shell. Anonymization layer concept absorbed into agent-layer design. |
| 2026-01-26 | phase-7.3-implementation-plan.md | Superseded — depends on archived SeleneChat architecture. |
| 2026-01-11 | things-checklist-integration-design.md | Required SeleneChat + cloud AI. Things integration now handled by agent-layer. |
| 2026-01-11 | selenechat-remote-access-design.md | Superseded by SeleneMobile (also archived). |
| 2026-01-05 | weekly-review-react-flow-design.md | "Present → React → File" paradigm. Depended on archived thread + task systems. |
| 2026-01-05 | selenechat-interface-inspiration-design.md | SeleneChat design reference. Design philosophy (Forest Study palette) could inspire web dashboard. |
| 2026-01-05 | selenechat-redesign-design.md | SeleneChat Forest Study design system. App archived. |
| 2026-01-01 | n8n-upgrade-design.md | Superseded by TypeScript replacement (2026-01-09). |
| 2026-01-04 | user-story-system-design.md | Replaced by simplified two-layer system |
| 2026-01-02 | plan-archive-agent-design.md | Deprioritized |
| 2026-01-02 | selenechat-auto-builder-design.md | Deprioritized |
| 2026-01-02 | feedback-pipeline-design.md | Deprioritized |
| 2026-01-02 | selenechat-uat-system-design.md | Deprioritized |
| 2026-01-03 | process-gap-fixes-design.md | Deprioritized |
| 2025-12-31 | ai-provider-toggle-design.md | Implemented |
| 2025-12-30 | task-extraction-planning-design.md | Implemented |
| 2025-12-30 | daily-summary-design.md | Implemented |
| 2025-12-31 | phase-7.2-selenechat-planning-design.md | Implemented |
| 2025-12-31 | workflow-lifecycle-management-design.md | Superseded |
| 2025-12-31 | workflow-standardization-design.md | Superseded by TS replacement |
| 2026-01-01 | selenechat-debug-system-design.md | Implemented |
| 2025-11-14 | ollama-integration-design.md | Implemented |
| 2025-11-14 | selenechat-database-integration-design.md | Implemented |
| 2025-11-15 | selenechat-clickable-citations-design.md | Implemented |
| 2025-11-27 | modular-context-structure.md | Implemented |
| 2025-11-30 | dev-environment-design.md | Implemented |
| 2025-11-25 | phase-7-1-gatekeeping-design.md | Superseded |
| 2026-01-02 | bidirectional-things-flow-design.md | Implemented |
| 2026-01-01 | project-grouping-design.md | Implemented |

</details>

---

## Workflow

### Creating a Design Doc

1. Use brainstorming skill to explore the idea
2. Write to `docs/plans/YYYY-MM-DD-topic-design.md`
3. Add entry to this INDEX in "Vision" section
4. Status: **Vision**

### Making It Ready

1. Add acceptance criteria (testable)
2. Complete ADHD check
3. Verify scope (< 1 week)
4. Move to "Ready" section
5. Status: **Ready**

### Starting Implementation

1. Create branch: `git worktree add -b feature-name .worktrees/feature-name main`
2. Copy BRANCH-STATUS.md template
3. Move doc to "In Progress" section
4. Follow GitOps stages (see `.claude/GITOPS.md`)
5. Status: **In Progress**

### Completing

1. Merge to main
2. Move doc to "Done" section
3. Complete closure ritual
4. Status: **Done**

---

## Related

- `templates/DESIGN-DOC-TEMPLATE.md` - Template for new designs
- `.claude/GITOPS.md` - Implementation workflow
- `.claude/PROJECT-STATUS.md` - Current project state
