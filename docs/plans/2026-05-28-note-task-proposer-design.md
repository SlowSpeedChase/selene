# Note → Task Proposer Agent

**Date:** 2026-05-28
**Status:** Ready
**Topic:** agent-layer, things-integration, executive-function, close-the-loop, adhd
**Source:** Lesson #6 in `2026-05-28-competitive-landscape-research.md` (Saner.ai surfaces "tasks from your recent notes")

---

## Vision

Selene's agent layer today only enriches *existing* Things tasks (`things-metadata-enricher` adds
notes/tags to tasks you already created). It waits for the task to exist. The competitive scan's
clearest gap-filler is the other direction: **read recent notes, find the ones that contain an
intention or action, and propose them as Things tasks** — which the user approves or rejects in
the dashboard already built for the enricher.

This closes the "thought → task" half of the broken loop described in
`2026-03-21-close-the-loop-design.md`, but scoped tightly and against the *current* agent-layer
architecture (not the archived task-extraction/threads systems). It stays inside the agent
contract that makes the layer trustworthy: **the agent proposes, you decide, nothing is created
without approval.**

---

## Goals / Non-Goals

**Goals**
- A new `note-task-proposer` agent that scans recent notes and proposes Things tasks for those expressing an actionable intention.
- Reuse the existing pipeline end-to-end: `BaseAgent` → `agent_actions` (pending) → `/dashboard/queue` → approve → `executeApproved` → `thingsExecutor`.
- Add the missing **task-creation** primitive: a `createTask` helper in `lib/things.ts` and a `things.create_task` action handler (neither exists today).
- A per-note dedupe marker so the same note is never proposed twice (including after a rejection).
- Honor the human-in-the-loop contract: zero tasks created without explicit approval.

**Non-Goals**
- Reviving the archived Task Extraction system or any `extracted_tasks`/`tasks` table — v1 reads `raw_notes`/`processed_notes` only and writes to Things, not to a Selene tasks table.
- Task *breakdown* into sub-steps — that's Lesson #5 (worksheets Phase 2), separate.
- Detecting task *completion* / momentum / the reverse loop — out of scope (the rest of close-the-loop).
- Auto-creating tasks, due dates, scheduling, or project routing logic beyond a single default destination.

---

## Architecture

Follows the existing agent pattern exactly (`things-metadata-enricher` is the reference
implementation).

```
note-task-proposer  (extends BaseAgent, src/agents/note-task-proposer.ts)
  collect(): recent notes where task_proposed_at IS NULL    ← uses processed notes
  reason():  per note → 1 Ollama call "is there an action here?"
             → ProposedAction { things.create_task, target_type: 'selene_note' }
             → stamp task_proposed_at on the note (skip stamp if Ollama errored)
        ↓ insertActions (status: pending)
  /dashboard/queue  → Approve / Reject           (existing UI, unchanged)
        ↓ approve → executeApproved (existing)
  thingsExecutor.execute('things.create_task')   ← NEW handler
        ↓
  lib/things.ts → createTask(name, {notes, tags}) ← NEW AppleScript helper → Things Inbox
```

### New action type

- `things.create_task`, `target_type: 'selene_note'`, `target_id = String(note.id)`.
- `payload: { name: string; notes?: string; tags?: string[] }`.
- `allowedActionTypes = ['things.create_task']` on the agent (the `BaseAgent.run()` validator already drops anything else).

### Agent: `src/agents/note-task-proposer.ts`

`collect()` — query recent, processed, not-yet-proposed notes (test_run IS NULL), limit ~20:

```sql
SELECT rn.id, rn.title, rn.content, pn.essence, pn.concepts
FROM raw_notes rn
LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
WHERE rn.test_run IS NULL
  AND rn.task_proposed_at IS NULL
  AND rn.created_at >= datetime('now', '-' || ? || ' days')
ORDER BY rn.created_at DESC
LIMIT ?
```

`reason()` — one Ollama call per note:

```
You are reviewing a personal note to see if it contains something the person wants to DO.

Note title: {title}
Note: {content (capped ~600 chars)}

If the note expresses a concrete action, task, or intention the person wants to take,
return a short imperative task name (≤ 8 words) and a one-line reason.
If it is a reflection, observation, or idea with no action, return action=false.

Respond with ONLY valid JSON:
{"action": true, "task": "Call dentist about crown", "reason": "Note says 'need to sort the crown'"}
OR
{"action": false}
```

- Parse defensively (reuse the `parseOllamaResponse` JSON-extraction pattern from the enricher).
- On `action:true` → push `ProposedAction` (confidence ~0.6; `rationale = "Create task \"{task}\" — from note \"{title}\": {reason}"` so the proposed task name is visible in the existing queue, which renders `rationale`).
- After each note is evaluated (true *or* false), stamp `task_proposed_at = now`. **If the Ollama call throws, do not stamp** — let it retry next run (mirrors how the enricher skips on error).

### Executor handler (`src/agents/executor.ts`)

```ts
thingsExecutor.register('things.create_task', async (action) => {
  const p = JSON.parse(action.payload) as { name: string; notes?: string; tags?: string[] };
  const id = createTask(p.name, { notes: p.notes, tags: p.tags });
  if (!id) throw new Error(`Failed to create Things task from note ${action.target_id}`);
});
```

(On failure the executor already reverts the action to `approved` for retry.)

### `lib/things.ts` — `createTask`

New helper mirroring `updateTaskNotes`/`addTagToTask` (AppleScript via `runAppleScriptFile`).
Default destination is the **Things Inbox** (ADHD-correct: the user triages in Things, we don't
guess a project). Returns the new to-do id (for logging/idempotency) or `null` on failure.

```applescript
tell application "Things3"
  set newTask to make new to do with properties {name:"…", notes:"…"}
  -- set tag names of newTask to {"…"}   (only if tags provided)
  return id of newTask
end tell
```

Escape `name`/`notes` the same way `updateTaskNotes` does (`\\` and `"`).

### Dedupe marker

Add column `task_proposed_at TEXT` to `raw_notes` (nullable), following the existing
`status_folio` / `last_reviewed_at` precedent (single `ALTER TABLE raw_notes ADD COLUMN …` in
the schema/migration path used for those columns). Set when the proposer evaluates a note;
`collect()` filters on `IS NULL`. Because it's stamped at *proposal* time (not approval), a
rejected proposal is never re-surfaced — the agent respects "no."

---

## Data flow example

1. Note captured: *"ugh I really need to renew the car registration before it lapses"*.
2. `note-task-proposer` run (CLI or scheduled) → Ollama → `{action:true, task:"Renew car registration", reason:"…before it lapses"}`.
3. `agent_actions` row: pending, `things.create_task`, target `selene_note` 412, payload `{name:"Renew car registration"}`. Note 412 stamped `task_proposed_at`.
4. Dashboard `/dashboard/queue` shows: **Create task "Renew car registration" — from note "…car registration…"** with Approve/Reject.
5. Approve → `createTask` → task lands in Things Inbox. Reject → nothing created, note stays stamped (won't re-propose).

---

## Acceptance Criteria

- [ ] `npx ts-node src/agents/note-task-proposer.ts` runs, scans recent notes, and creates `pending` `things.create_task` actions for action-bearing notes only (reflective notes produce none).
- [ ] Proposed actions appear in `/dashboard/queue` with the proposed task name visible.
- [ ] Approving an action creates a to-do in the Things Inbox with that name (manual verification — AppleScript not unit-testable).
- [ ] Rejecting an action creates nothing, and re-running the agent does **not** re-propose that note.
- [ ] Re-running with no new notes proposes nothing (dedupe via `task_proposed_at` confirmed).
- [ ] An Ollama failure on a note leaves it un-stamped (eligible next run); the batch continues for other notes.
- [ ] `things.create_task` is in the agent's `allowedActionTypes`; a stray disallowed action is filtered by `BaseAgent.run()`.
- [ ] Unit tests (test DB, `test_run` markers): prompt builder, JSON parse (true/false/garbage), `collect` dedupe filter, executor handler with a mocked `createTask`. Cleaned up via `cleanup-tests.sh`.
- [ ] No production-DB writes during testing; no Things tasks created during automated tests (executor mocked).

---

## ADHD Check

- **Closes a real loop:** the "I wrote it down but never turned it into an action" gap is a core ADHD failure mode; this catches intentions before they evaporate.
- **Reduces friction:** no manual re-reading of notes to extract to-dos; the system drafts them.
- **Trust / safety:** nothing is created without approval — preserves the agent contract that keeps the layer usable. No surprise tasks.
- **No guilt:** proposals are offers; rejecting one is frictionless and final (won't nag again).
- **Realistic:** Inbox-only destination, one task per note, capped batch — no over-scheduling.

---

## Scope Check

~2–3 days. Single new agent + one helper + one handler + one column + tests. All scaffolding
(BaseAgent, agent_actions, dashboard queue, approve→execute path) already exists. No blockers.

| Piece | Effort |
|-------|--------|
| `createTask` helper in `lib/things.ts` | Small (1–2 hrs, mirrors `updateTaskNotes`) |
| `things.create_task` executor handler | Trivial |
| `note-task-proposer.ts` agent (collect/reason/report) | Medium (~1 day, follows enricher) |
| `task_proposed_at` column + dedupe filter | Small |
| Unit tests + manual Things verification | Medium |

---

## Open Questions

1. **Schedule vs. on-demand.** The enricher runs via CLI with a project argument. For v1, recommend CLI/manual (same as enricher) so the user controls when scanning happens; add a `com.selene.note-task-proposer` launchd plist (e.g. once daily after `daily-summary`) as a fast follow if it proves useful. *Not* enabled by default — proactive scanning should be opt-in.
2. **Destination.** Inbox (recommended, ADHD-correct triage) vs. a configurable project via agent `config`. Start Inbox-only; the `upsertAgent({config})` slot already exists if we want a project later.
3. **Confidence threshold / batch cap.** Start: propose all `action:true` results, cap the batch at ~10 actions per run to keep the approval queue reviewable. Tune after first real run.
4. **Should the queue render `payload` generically?** v1 puts the task name in `rationale` (already rendered), so no dashboard change is required. Optional polish: surface `payload.name` explicitly in `/dashboard/queue` for all create-type actions.
5. **Overlap with worksheets' `free_capture` → `new_note`.** Different surface (worksheet vs. background scan) and different output (note vs. task); no conflict, but both should write through the same `connections`/marker conventions if a follow-up links the task back to its source note (deferred).

---

## Related

- `docs/plans/2026-05-28-competitive-landscape-research.md` — Lesson #6 (origin)
- `docs/plans/2026-03-21-close-the-loop-design.md` — the broader loop; this implements its "thought → task" arm against the current agent layer
- `src/agents/base-agent.ts`, `src/agents/things-metadata-enricher.ts`, `src/agents/executor.ts` — pattern + extension points
- `src/lib/things.ts` — `createTask` lands here (alongside `updateTaskNotes`/`addTagToTask`)
- `src/routes/dashboard.ts`, `src/routes/agents.ts` — approval queue + approve→execute path (reused unchanged)
- `src/lib/agent-db.ts` — `agent_actions` schema, `target_type: 'selene_note'` already supported
- `docs/plans/2026-05-28-agentic-digest-lead-design.md` — sibling Ready doc (Lesson #1)
