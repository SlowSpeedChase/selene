# Agent Layer Design

**Date:** 2026-05-23
**Status:** Ready
**Topic:** agents, orchestration, things, personal-assistant

---

## Vision

Selene operates as a personal archivist and librarian at its foundation — faithfully capturing, indexing, and cross-referencing everything the user has thought and written. The agent layer builds on that foundation as a personal assistant: scoped, structured agents that work through the archive and external systems (Things, Calendar, Email), propose changes for human approval, and execute approved actions via deterministic process code.

The human-in-the-loop contract: agents work continuously, pause when they need input, surface reports for review, and resume after approval. Nothing executes without explicit user approval.

---

## Design Principles

- **Local-first**: Ollama only for all LLM reasoning. No cloud API calls in v1. Architecture designed to add Claude API later for non-sensitive structural reasoning.
- **Propose, don't execute**: Agents generate typed action lists; deterministic process code executes them.
- **Closed action vocabulary**: `action_type` is a strict enum per agent. LLMs can only propose known operations.
- **Reports everywhere**: Delivered to Apple Notes, Obsidian, and web dashboard. Read anywhere, act from dashboard.
- **Registry-as-table**: Agent config lives in SQLite, not code. Enable/disable/reconfigure without deployment.

---

## Architecture

### Layers

```
+----------------------------------------------------------+
| AGENT LAYER                                              |
| Scoped agents → Ollama reasoning → Action list           |
| Agent manager → Job queue → Approval → Process code      |
+----------------------------------------------------------+
          ↓ reads from / writes back to
+----------------------------------------------------------+
| FOUNDATION: ARCHIVIST + LIBRARIAN                        |
| Capture (Drafts, e-ink, voice) → SQLite                  |
| Process (Ollama concept extraction, essences)            |
| Browse (Obsidian export, daily digest)                   |
+----------------------------------------------------------+
```

### Anonymization Layer

`src/lib/anonymize.ts` — sits at the **share boundary**: any data leaving the local system (debugging sessions, future cloud API calls) passes through it.

Two-pass approach:
1. **Regex pass** — structured PII: email addresses, phone numbers, URLs, dates, UUIDs
2. **Ollama NER pass** — contextual PII: names, places, organizations, account references

Output: `{ text: string, tokenMap: Record<string, string> }`
- `text` contains replacements: `[PERSON_1]`, `[EMAIL_1]`, `[PLACE_1]`
- `tokenMap` stored locally only — never leaves the machine

Debug usage:
```bash
npx ts-node scripts/anonymize-debug.ts <data-source>
```

Does **not** apply to Apple Notes or Obsidian delivery (local systems).

---

## Data Model

Three new SQLite tables added to `data/selene.db`:

### `agent_registry`
```sql
CREATE TABLE agent_registry (
  agent_name TEXT PRIMARY KEY,
  description TEXT NOT NULL,
  schedule TEXT,                    -- cron expression
  allowed_action_types TEXT NOT NULL, -- JSON array
  enabled INTEGER NOT NULL DEFAULT 1,
  last_run_at TEXT,
  config TEXT                       -- JSON, agent-specific config
);
```

### `agent_jobs`
```sql
CREATE TABLE agent_jobs (
  id TEXT PRIMARY KEY,
  agent_name TEXT NOT NULL,
  status TEXT NOT NULL,             -- running | paused | complete | error
  started_at TEXT NOT NULL,
  completed_at TEXT,
  summary TEXT,
  FOREIGN KEY (agent_name) REFERENCES agent_registry(agent_name)
);
```

### `agent_actions`
```sql
CREATE TABLE agent_actions (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL,
  action_type TEXT NOT NULL,        -- closed enum per agent
  target_id TEXT NOT NULL,
  target_type TEXT NOT NULL,        -- things_task | selene_note | calendar_event
  payload TEXT NOT NULL,            -- JSON
  rationale TEXT NOT NULL,
  confidence REAL NOT NULL,         -- 0.0–1.0
  status TEXT NOT NULL DEFAULT 'pending', -- pending | approved | rejected | executing | done
  created_at TEXT NOT NULL,
  reviewed_at TEXT,
  executed_at TEXT,
  FOREIGN KEY (job_id) REFERENCES agent_jobs(id)
);
```

### `agent_reports`
```sql
CREATE TABLE agent_reports (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,               -- markdown
  delivered_to TEXT NOT NULL DEFAULT '[]', -- JSON array of channels
  created_at TEXT NOT NULL,
  FOREIGN KEY (job_id) REFERENCES agent_jobs(id)
);
```

---

## Agent Architecture

Each agent is a narrowly scoped TypeScript module with four parts:

1. **Input collector** — reads from Selene DB and/or external systems via typed queries. Agents only see what they're scoped to see.
2. **Ollama reasoning step** — sends collected data to local model, asks for a structured JSON action list: `[{ action_type, target_id, target_type, payload, rationale, confidence }]`
3. **Job queue writer** — writes proposed actions to `agent_actions` with status `pending`. Agent pauses here and sets job status to `paused`.
4. **Process code** — deterministic TypeScript functions registered per `action_type`. Executed only after approval. The LLM never executes directly.

Agents run on launchd schedules. They stop themselves when they have pending approvals. The agent manager resumes them after approval.

---

## Agent Manager

A persistent TypeScript service (`src/workflows/agent-manager.ts`) managed by a new launchd agent (`com.selene.agent-manager`). Always running alongside the server.

**Responsibilities:**
- **Registry** — maintains `agent_registry`, enforces allowed action types
- **Orchestration** — starts/stops agents, prevents concurrent modification of the same target
- **Escalation** — re-surfaces reports via additional channels if paused >4 hours without review
- **Health monitoring** — detects stuck/errored jobs, restarts or flags
- **Controls** — Fastify endpoints:
  - `GET /agents/status` — all agent status
  - `POST /agents/:name/run` — trigger manual run
  - `POST /agents/:name/pause` — pause an agent
  - `GET /agents/:name/jobs` — job history
  - `POST /agent-actions/:id/approve` — approve an action
  - `POST /agent-actions/:id/reject` — reject an action
  - `PUT /agent-actions/:id` — edit and approve

---

## Web Dashboard

Served by Fastify under `/dashboard`. Server-rendered HTML with minimal JavaScript. Accessible on local network (iPad, Mac, phone).

**Four views:**

**Home** — agent status cards (running/paused/idle), pending approval count badge, recent activity feed.

**Approval Queue** — grouped by agent. Each pending action list shows:
- Report summary (what the agent found)
- Each proposed action with rationale and confidence score
- Controls: `Approve All` | `Approve Selected` | `Reject` | `Edit` (modify action before approving)

**Reports** — all agent reports, full markdown, searchable and filterable by agent and date.

**Agent Manager** — enable/disable agents, trigger runs manually, view allowed action types and last run time.

---

## Report Delivery

Triggered by the agent manager when a report is written. Tracks delivery in `agent_reports.delivered_to`.

| Channel | Format | Timing |
|---------|--------|--------|
| Web Dashboard | Always present | Immediately |
| Apple Notes | One pinned note per agent, appended each run | Immediately (same pattern as daily digest) |
| Obsidian | `/agent-reports/YYYY-MM-DD-agent-name.md` | Hourly sync |
| macOS Notification | Short alert with pending count | When paused >4 hours without review |

---

## First Agent: Things Task Metadata Enricher

**Scope:** single Things project (configurable in `agent_registry.config`).

**What it does:**
1. Reads tasks from target project via AppleScript
2. For each task missing notes or tags: queries Selene note archive for related content on that topic
3. Sends `{ taskTitle, relatedNotes }` to Ollama: *"Suggest tags and a one-sentence context note for this task"*
4. Builds action list with `things.update_notes` and `things.add_tag` actions
5. Writes report + sets job to `paused`
6. On approval: executes via AppleScript

**Allowed action types:**
- `things.update_notes`
- `things.add_tag`

**Why this first:**
- Highest-value external target
- Lower privacy sensitivity than email
- Demonstrates the Selene archive serving the agent layer (librarian → assistant)
- Full loop proof: Ollama → action list → queue → approval → AppleScript execution
- Scoped to one project — evaluate quality before expanding

---

## Acceptance Criteria

- [ ] Anonymization layer (`src/lib/anonymize.ts`) — two-pass, token map, debug script
- [ ] Three SQLite tables created and migrated
- [ ] Agent manager service running via launchd
- [ ] Web dashboard with four views accessible at `localhost:5678/dashboard`
- [ ] Report delivery to Apple Notes and Obsidian
- [ ] Things Task Metadata Enricher agent running end-to-end
- [ ] Full approval loop: pending → approved → executed via AppleScript
- [ ] Agent pauses correctly when awaiting approval, resumes after

## ADHD Check

- **Reduces friction**: agents do the tedious metadata work; you only approve
- **Visible**: reports delivered to Apple Notes (existing habit), dashboard, Obsidian
- **Externalizes cognition**: agents surface what needs attention; nothing hidden
- **Realistic scope**: single project for first agent, expand by config not code

## Scope Check

Estimated work: 1–2 weeks for full v1 (anonymization layer + data model + agent manager + dashboard + first agent). Dashboard is the largest surface — can be de-risked by building the approval API first and adding UI incrementally.
