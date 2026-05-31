# Living System Map — a codebase-comprehension system that can't go stale

**Status:** Done (core shipped 2026-05-31; pre-push enforcement follow-up 2026-05-31)
**Date:** 2026-05-31
**Topic:** documentation, comprehension, drift-prevention, codegen, hooks

---

## Follow-up (2026-05-31): pre-push enforcement

The session-end Stop hook is a *best-effort* reminder — it keys on the working
tree (`git status`), so a workflow edited **and committed** within one session
leaves a clean tree and never triggers it. To close that gap, a **pre-push git
hook** (`scripts/hooks/pre-push`, activated via the existing relative-symlink
convention `.git/hooks/pre-push → ../../scripts/hooks/pre-push`) runs
`gen-system-map.ts --check` on every push and **blocks the push** if the
committed map is stale. `git push --no-verify` is the deliberate bypass. This
turns the guarantee from "you'll probably be reminded" into "you can't ship
drift to origin." Always-run (not scoped to changed files) for robustness; the
~2-3s ts-node cost per push is negligible.

---

## Problem

As Selene grows, two pains compound:

1. **Stale docs / drift** — the map exists but can't be trusted. You (or a Claude session) act on outdated info.
2. **No mental model** — hard to hold the whole system in your head; you want a zoomable big-picture view.

Both pains trace to **one root cause**: the *facts* about the system (which workflows exist, what they run on, what they read and write) are **hand-copied into prose in several places**. So they drift, and there's no single trustworthy place to zoom into.

### Evidence (caught red-handed, 2026-05-31)

The codebase has **12 workflows**. The docs disagree, and disagree with each other:

| Source | Workflows it lists | Accuracy |
|--------|--------------------|----------|
| **Reality** — `src/workflows/*.ts` | ingest, process-llm, distill-essences, export-obsidian, daily-summary, send-digest, agent-manager, eink-ingest, voice-ingest, folio-feedback, generate-worksheet, synthesize-topics | ground truth |
| `CLAUDE.md` (single entry point, loaded every session) | first 6 only | **50% stale** |
| `docs/backend-block-diagrams.md` | first 9 (missing folio-feedback, generate-worksheet, synthesize-topics) | 75% — fresher but still wrong |

The staleness is worst in the document both human and AI trust *first*. The freshness machinery that should prevent this already exists — a Stop hook nags "update the diagram" and a `diagram-sync` skill performs the update — but it relies on a human or agent *choosing* to do the sync, and that link is silently broken. **Nagging doesn't prevent drift; only generation does.** A fact read from code can't be "6" when the truth is "12".

---

## Approach

**Generate the facts; hand-write only the meaning; arrange both as a three-level zoom ladder with a generated manifest as the trustworthy pivot.**

### The zoom ladder (kills "no mental model")

```
L0  CLAUDE.md            "What is this? Where do I go?"        ← pointers only, ZERO facts to drift
        │
L1  docs/SYSTEM-MAP.md   the zoomable index: every workflow as a one-liner —
   (mostly GENERATED)    name · schedule · trigger · in → out · link to code & diagram
        │
L2  docs/backend-block-diagrams.md   deep ASCII flows + the code itself
    + src/workflows/*.ts             ← hand-drawn meaning, deep detail
```

You read top-down only as far as you need. The big picture (L1) is one screen, always correct, and every line is a link into the next zoom level.

### The generator (kills "stale docs")

A small script — `scripts/gen-system-map.ts` — reads the real source of truth:

- `src/workflows/*.ts` — the workflow inventory (excluding `*.test.ts`)
- `launchd/*.plist` — the schedule for each (`StartInterval` / `StartCalendarInterval`)

…and emits the factual table into `docs/SYSTEM-MAP.md` **between `<!-- GENERATED:workflows START -->` / `<!-- GENERATED:workflows END -->` markers**. Re-run it and the table cannot be wrong, because it read the truth. Hand-written narrative lives *outside* the markers and is never touched by the generator.

**What facts come from where:**

| Fact | Source | How extracted |
|------|--------|---------------|
| Workflow exists | `src/workflows/X.ts` (not `.test.ts`) | filename |
| Schedule | `launchd/com.selene.X.plist` | parse `StartInterval` (seconds) or `StartCalendarInterval` |
| One-line purpose | a `// @map:` doc-comment at the top of each workflow | regex; falls back to "—" if absent |
| Reads / writes | same `// @map:` comment (e.g. `reads: raw_notes; writes: processed_notes`) | regex |

The `// @map:` convention keeps the *meaning* next to the code it describes (so it drifts far less), while the generator harvests it into the central table. A workflow with no `// @map:` comment still appears in the table (with `—` for purpose) — so a *new, undocumented* workflow can never be silently missing from the map.

### The guard (makes drift impossible to ignore)

The generator supports `--check`: regenerate in memory, diff against the committed `SYSTEM-MAP.md`, exit non-zero if they differ. Extend the existing Stop hook (`.claude/hooks/session-end-reminders.sh`) so that when a `src/workflows/*.ts` or `launchd/*.plist` file changed this session, it runs `gen-system-map --check` and surfaces the diff. Same pattern as the existing `launchd-auditor` reminder — it builds on machinery you already have rather than adding a new system.

### Deliberately NOT building (YAGNI)

- **No cross-repo map** — you said fragmentation across the 5 repos isn't the pain.
- **No scheduled audit agent** — the Stop hook catches drift the moment it happens, which is strictly better than an after-the-fact periodic diff. Adds no new launchd agent.
- **No new diagram tool / rendering engine** — L2 stays the existing hand-drawn ASCII block diagrams.
- **No DB-schema / config generation (for now)** — the workflow+schedule manifest is the highest-value, highest-drift surface. The marker mechanism leaves room to add a `<!-- GENERATED:schema -->` block later if it earns its keep.

### First concrete win

The generator's first run produces the correct 12-workflow table. We then:
1. Commit `SYSTEM-MAP.md` with the real inventory.
2. Edit `CLAUDE.md` so its "6 workflows" count is replaced by a *pointer* to `SYSTEM-MAP.md` (L0 stops restating facts it can't keep current).
3. Add a one-line "see SYSTEM-MAP.md for the live inventory" header to `backend-block-diagrams.md` so L2 defers to L1 on the inventory.

---

## Acceptance Criteria

- [ ] `scripts/gen-system-map.ts` exists; running it writes a workflow table into `docs/SYSTEM-MAP.md` listing **all 12** current workflows with schedule + reads/writes.
- [ ] The generated table is bounded by `<!-- GENERATED -->` markers; hand-written prose outside the markers survives a regeneration untouched.
- [ ] `gen-system-map --check` exits non-zero when the committed file is out of date, zero when current.
- [ ] The Stop hook runs `--check` when a workflow or plist changed this session and surfaces any drift.
- [ ] `CLAUDE.md` no longer states a workflow *count*; it points to `SYSTEM-MAP.md`.
- [ ] A reader can go CLAUDE.md → SYSTEM-MAP.md → a specific workflow file / diagram section in two clicks.

## ADHD Check

- **Reduces friction?** Yes — one always-correct screen replaces hunting across stale docs and re-reading code to rebuild the mental model.
- **Visible?** Yes — the whole system on one zoomable page; externalizes the "what runs when, reading/writing what" you currently hold in your head.
- **Externalizes cognition?** Yes — the generator, not your memory, is responsible for keeping the inventory true.

## Scope Check

- [ ] < 1 week of focused work — one script (~150 lines), one doc, one `// @map:` comment per workflow (12), one hook edit. Well under.
- [ ] No blockers.

---

## User-Facing Change?

**Yes** — this changes how *you* navigate and understand the system (and is itself a documented capability). Wrap-up will add/update a short guide under `docs/guides/features/` (e.g. `system-map.md`) and link it from `docs/USER-EXPERIENCE.md`.

---

## Open Questions (resolve during planning)

1. Schedule rendering: show raw `StartInterval` seconds, or humanize ("every 5 min")? (Lean: humanize, since L1 is for comprehension.)
2. Should `server.ts` (the always-on webhook server) and dev/prod infra plists (`dev.server`, `prod.deploy-watcher`) appear in the table, or only the processing workflows? (Lean: a separate "always-on / infra" mini-table so the picture is complete without muddying the workflow list.)
3. `// @map:` comment format — settle the exact grammar so the regex is simple and the comment reads naturally to a human.
