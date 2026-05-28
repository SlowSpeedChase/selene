# Leverage Rollout Plan

**Date:** 2026-05-28
**Status:** Plan (sequencing for later — not itself a feature design)
**Topic:** roadmap, planning, gitops, competitive-leverage
**Covers:** the 8 lessons in `2026-05-28-competitive-landscape-research.md`

---

## Purpose

The "for later" build plan: turn the competitive-scan lessons into shipped features, in a
sensible order, with executable checklists for the two that are already **Ready**
(`2026-05-28-agentic-digest-lead-design.md` #1, `2026-05-28-note-task-proposer-design.md` #6).
Pick this up in a future session and start at Wave 1 without re-deciding anything.

Each feature ships on its **own** branch via the normal GitOps flow (worktree → BRANCH-STATUS →
planning/dev/testing/docs/review/ready). The features are independent — none blocks another.

---

## Sequencing

### Wave 1 — Quick wins (prompt-level, ~0.5 day each)
Land these first; they're small, high-signal, and touch isolated code.

| # | Lesson | Where | Status |
|---|--------|-------|--------|
| **1** | Agentic digest lead line | `daily-summary.ts` | **Ready** — checklist below |
| 4 | Tensions / changes-of-mind in synthesis | synthesis prompt | Folds into synthesis build (not standalone) |
| 3 | Related notes at capture | `ingest.ts` + worksheet retrieval path | Needs a short design doc first |
| 8 | Calm + local as principle | `.claude/ADHD_Principles.md` framing | Adopt now (no build) — see note below |

### Wave 2 — Bigger bets (multi-day)
| # | Lesson | Where | Status |
|---|--------|-------|--------|
| **6** | Note → Task proposer agent | `src/agents/` + `lib/things.ts` | **Ready** — checklist below |
| 5 | Task-breakdown worksheet | worksheets Phase 2 generator | Already scoped in worksheets design |
| 2 | Spaced resurfacing into digest | PKM browse `pkm_review_state` + digest | Build with the PKM browse layer |

### Wave 3 — Parked
| # | Lesson | Gate |
|---|--------|------|
| 7 | Audio digest of topics | Only if a *simple* local TTS exists; do not revive archived voice stack |

**Recommended first session:** ship #1 (half a day, end-to-end win), then start #6.

---

## Checklist — #1 Agentic Digest Lead Line

Design: `2026-05-28-agentic-digest-lead-design.md`. All work in `src/workflows/daily-summary.ts`.

**Dev**
- [ ] Add `LEAD_PROMPT` constant (text in the design doc) near `SUMMARY_PROMPT`.
- [ ] Add a `firstLine(s: string): string` helper (trim, take first non-empty line).
- [ ] After `summary` is generated and `if (await isAvailable())`: build `{topNoteEssences}` from the existing `notes` array (most recent ~8, reuse the `notesText` essence/concept/title fallback), call `generate(LEAD_PROMPT…, { temperature: 0.3 })`, run through `firstLine`.
- [ ] Prepend `` `Worth your attention: ${lead}\n\n` `` to `digest` before `writeFileSync(digestPath, …)`.
- [ ] Offline guard: when `isAvailable()` is false, write the digest with **no** lead and no placeholder.

**Testing**
- [ ] Unit test `firstLine` (multi-line input → one line).
- [ ] Unit test offline skip: stub `isAvailable()` → false, assert no "Worth your attention" prefix.
- [ ] Manual: test-env run (`SELENE_ENV` test path → `sent/` file) with real-ish notes; read the line for specificity. Then one real run; confirm it renders as the first `<p>` in "Selene Daily".
- [ ] `cleanup-tests.sh` any test rows used.

**Docs**
- [ ] Update `docs/guides/features/daily-digest.md` (lead line is user-visible).
- [ ] Update `docs/USER-EXPERIENCE.md` morning-digest section.
- [ ] `PROJECT-STATUS.md` + move doc to Done in `INDEX.md`.

**Verify it's real:** run `daily-summary.ts`, then `send-digest.ts`, and look at the actual
Apple Note — the first paragraph should name a specific topic + next move, not "N notes captured."

---

## Checklist — #6 Note → Task Proposer Agent

Design: `2026-05-28-note-task-proposer-design.md`. Build in stages; each stage is independently testable.

**Stage A — task-creation primitive (do first, it's the missing capability)**
- [ ] `src/lib/things.ts`: add `createTask(name, opts?: { notes?; tags?; projectName? }): string | null` — AppleScript `make new to do`, default destination **Inbox**, escape like `updateTaskNotes`, return new id or null.
- [ ] `src/agents/executor.ts`: `thingsExecutor.register('things.create_task', …)` → parse `{name, notes?, tags?}` → `createTask` → throw on null.
- [ ] Unit test the handler with a mocked `createTask` (no real AppleScript in tests).

**Stage B — dedupe marker**
- [ ] Add `task_proposed_at TEXT` (nullable) to `raw_notes`, following the `status_folio` / `last_reviewed_at` column-add precedent.

**Stage C — the agent**
- [ ] `src/agents/note-task-proposer.ts`: extend `BaseAgent`; `allowedActionTypes = ['things.create_task']`.
- [ ] `collect()`: the recent + processed + `task_proposed_at IS NULL` + `test_run IS NULL` query (in design doc), limit ~20.
- [ ] `reason()`: per note → `generate()` with the "is there an action?" prompt → defensive JSON parse (reuse enricher's `{…}`-extraction pattern) → on `action:true` push `ProposedAction` (`target_type:'selene_note'`, task name in `rationale`); **stamp `task_proposed_at` per note, but only if the Ollama call did not throw**.
- [ ] `buildReport()` mirroring the enricher (link to `/dashboard`).
- [ ] CLI entry point (like the enricher) + a `register({description, …})` call.

**Stage D — tests + manual verify**
- [ ] Unit (test DB, `test_run` markers): prompt builder; parse true/false/garbage; `collect` dedupe filter; executor handler.
- [ ] Manual: seed a couple of `test_run` notes (one action-bearing, one reflective) → run agent → only the action-bearing one proposes → approve in `/dashboard/queue` → confirm a Things **Inbox** task → reject another → re-run → confirm no re-propose.
- [ ] `cleanup-tests.sh` the test run.

**Stage E — docs**
- [ ] Update `docs/guides/features/agent-enrichments.md` (new "proposes tasks from notes" capability) + `USER-EXPERIENCE.md`.
- [ ] `PROJECT-STATUS.md` + move doc to Done in `INDEX.md`.

**Decisions already locked (don't re-litigate):** Inbox-only destination; manual CLI run for v1
(launchd opt-in later, off by default); propose all `action:true`, cap batch ~10; task name lives
in `rationale` so the existing queue needs no change.

---

## Wave 1 freebie — Lesson #8 (adopt now, no build)

Two product principles to fold into `.claude/ADHD_Principles.md` whenever next editing it:
1. **No streaks, no guilt mechanics, ever** — resurfacing/proposals are offers, never "you missed N days."
2. **Lead positioning with "your notes never leave your machine"** — the one differentiator no ADHD-marketed competitor has.

No code; just guardrails for future feature decisions.

---

## How to resume (future session)

1. **Session-start ritual** (CLAUDE.md): if in a worktree, `git fetch origin && git rev-list --count HEAD..origin/main`; rebase if behind.
2. Read the relevant design doc (#1 or #6) — they carry the full spec; this file carries only the *order* and the *checklist*.
3. Cut the branch per GitOps:
   ```bash
   git worktree add -b agentic-digest-lead .worktrees/agentic-digest-lead main   # (or note-task-proposer)
   cp templates/BRANCH-STATUS.md .worktrees/agentic-digest-lead/
   ```
4. Paste that feature's checklist (above) into the new `BRANCH-STATUS.md` and walk the stages.
5. On merge: move the design doc to **Done** in `INDEX.md`, write/update the feature guide, refresh `PROJECT-STATUS.md`.

**Start here next time:** Wave 1 → #1 (ship it), then Wave 2 → #6 Stage A.

---

## Related

- `docs/plans/2026-05-28-competitive-landscape-research.md` — the lessons + anti-patterns
- `docs/plans/2026-05-28-agentic-digest-lead-design.md` — #1 full spec
- `docs/plans/2026-05-28-note-task-proposer-design.md` — #6 full spec
- `.claude/GITOPS.md` — branch workflow + session-start ritual
- `templates/BRANCH-STATUS.md` — per-branch stage tracker
