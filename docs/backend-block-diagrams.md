# Backend Block Diagrams

**Last Updated:** 2026-06-11
**Purpose:** Visual representations of Selene's backend architecture and data flows

> **Inventory of record:** [docs/SYSTEM-MAP.md](SYSTEM-MAP.md) (generated from code + plists). This file is the *deep* view; if the two ever disagree on which workflows exist or their schedules, SYSTEM-MAP.md wins.

---

## 1. System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CAPTURE LAYER                            │
│                                                                 │
│  ┌──────────┐                                                  │
│  │  Drafts  │ ──────┐                                          │
│  │   App    │       │  HTTP POST                               │
│  └──────────┘       │  (JSON payload)                          │
│                     ↓                                          │
│  ┌──────────┐  ┌─────────────────┐                             │
│  │ Shortcuts│→ │ Fastify Server  │ (always running, port 5678) │
│  └──────────┘  └─────────────────┘                             │
│                         ↓ ingest.ts                            │
│                    INSERT INTO raw_notes                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Every 30 min: eink-ingest.ts                            │  │
│  │  Scan ~/kindle-export/ for new PDFs → Ollama OCR         │  │
│  │  → INSERT INTO raw_notes                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Every 30 min: voice-ingest.ts                           │  │
│  │  Scan ~/Voice Memos/ for new .m4a → Whisper transcribe   │  │
│  │  → INSERT INTO raw_notes                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Server routes (iPad): generate-worksheet.ts             │  │
│  │  GET /api/worksheets/today → build daily review          │  │
│  │  POST /api/worksheets/:id/answers → INSERT raw_notes     │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                     PROCESSING LAYER                            │
│                   (launchd scheduled jobs)                      │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Every 5 min: process-llm.ts                           │    │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────────────┐  │    │
│  │  │  SELECT  │ →  │  Ollama  │ →  │     INSERT       │  │    │
│  │  │ pending  │    │mistral:7b│    │ processed_notes  │  │    │
│  │  │  notes   │    │          │    │ concepts, theme, │  │    │
│  │  └──────────┘    └──────────┘    │ energy, essence  │  │    │
│  │                                   └──────────────────┘  │    │
│  │  Extracts: concepts, themes, energy, sentiment, essence  │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Every 5 min: distill-essences.ts                      │    │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────────────┐  │    │
│  │  │  SELECT  │ →  │  Ollama  │ →  │     UPDATE       │  │    │
│  │  │ notes    │    │mistral:7b│    │ processed_notes  │  │    │
│  │  │ missing  │    │          │    │    .essence      │  │    │
│  │  │ essence  │    └──────────┘    └──────────────────┘  │    │
│  │  └──────────┘                                           │    │
│  │  Backfills and retries failed essence extractions       │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Every 15 min: agent-manager.ts                        │    │
│  │                                                         │    │
│  │  READ agent_registry (which agents are enabled)        │    │
│  │       ↓                                                 │    │
│  │  For each agent: fetch context → Ollama reason →       │    │
│  │    INSERT proposed actions into agent_jobs             │    │
│  │       ↓                                                 │    │
│  │  Export pending jobs to Apple Notes + Obsidian         │    │
│  │       ↓ (user reviews and approves)                    │    │
│  │  ActionExecutor: run approved actions                  │    │
│  │    → INSERT INTO action_execution_log                  │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Every 15 min: vault-feedback.ts                       │    │
│  │  Scan vault "Your note" sections → new author feedback │    │
│  │  → INSERT facts.note_feedback + re-pend the note       │    │
│  │  (export-obsidian also scans right before rendering)   │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Hourly: export-obsidian.ts                            │    │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────────────┐  │    │
│  │  │  SELECT  │ →  │  Ollama  │ →  │  WRITE .md files │  │    │
│  │  │processed │    │ curate + │    │  to vault/       │  │    │
│  │  │  notes   │    │ organize │    │  notes/ mocs/    │  │    │
│  │  └──────────┘    └──────────┘    │  Dashboard.md    │  │    │
│  │                                   └──────────────────┘  │    │
│  │  Exports: LLM-curated notes, 8-category MOCs, dashboard │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Daily midnight: daily-summary.ts                      │    │
│  │  SELECT today's notes → Ollama → INSERT daily_summaries│    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Daily 6am: send-digest.ts                             │    │
│  │  SELECT daily_summaries → WRITE to Apple Notes         │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Daily 2am: synthesize-topics.ts                       │    │
│  │  SELECT processed_notes → cluster into 8 categories    │    │
│  │  → Ollama synthesize → INSERT topic_clusters,          │    │
│  │  topic_note_links, synthesis_meta                      │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Every 5 min: folio-feedback.ts                        │    │
│  │  SELECT Kindle-Scribe annotations → WRITE markdown     │    │
│  │  feedback files into each Folio project repo           │    │
│  │  (Folio is a SEPARATE repo — boundary seam only)       │    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                      DELIVERY LAYER                             │
│                                                                 │
│  ┌──────────────────────┐     ┌──────────────────────────┐    │
│  │  Obsidian Vault       │     │  Apple Notes             │    │
│  │                       │     │                          │    │
│  │  vault/notes/*.md     │     │  "Selene Daily Digest"   │    │
│  │  vault/mocs/*.md      │     │  (pinned, daily update)  │    │
│  │  vault/Dashboard.md   │     │                          │    │
│  │  vault/synthesis/     │     │  "Selene Agent Report"   │    │
│  │  (planned)            │     │  (agent proposed actions)│    │
│  └──────────────────────┘     └──────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Note Lifecycle Timeline

```
T+0 min     User captures note in Drafts
                        ↓
            HTTP POST → localhost:5678/webhook/api/drafts
                        ↓
            server.ts → ingest.ts
                        ↓
            INSERT INTO raw_notes
            {
              id: "uuid",
              title: "I need to research signature scents",
              content: "Full note text...",
              created_at: "2026-05-24T10:00:00Z",
              content_hash: "abc123..."  ← Duplicate detection
            }
            ✓ Status: Captured
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+5 min     process-llm.ts runs (launchd trigger)
                        ↓
            SELECT raw_notes not yet in processed_notes
            Found: [note above]
                        ↓
            Send to Ollama mistral:7b
            Prompt: "Extract concepts, themes, energy, essence..."
                        ↓
            Ollama returns:
            {
              concepts: ["scent", "research", "identity"],
              primary_theme: "self-expression",
              energy_level: "medium",
              essence: "Exploring signature scents as identity expression"
            }
                        ↓
            INSERT INTO processed_notes
            ✓ Status: Processed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+5-10 min  distill-essences.ts runs (if essence missing or failed)
                        ↓
            SELECT processed_notes WHERE essence IS NULL
            Retry Ollama call for essence only
            ✓ Status: Essence filled

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+15 min    agent-manager.ts runs
                        ↓
            Check agent_registry for enabled agents
            (e.g., Things Enricher agent)
                        ↓
            Fetch recent processed notes + context
            Send to Ollama for agent reasoning
                        ↓
            Proposed action inserted into agent_jobs:
            {
              agent: "things-enricher",
              action_type: "ENRICH_TASK",
              payload: { task_title: "...", notes: [...] }
              status: "pending_review"
            }
                        ↓
            Written to Apple Notes agent report
            ✓ Status: Agent proposed action, awaiting approval

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+60 min    export-obsidian.ts runs
                        ↓
            SELECT processed_notes not yet exported
                        ↓
            Ollama: select + curate notes for vault
            Generate markdown with wikilinks + frontmatter
                        ↓
            WRITE to vault/notes/<slug>.md
            UPDATE 8-category MOC indexes
            UPDATE vault/Dashboard.md
            ✓ Status: Exported to Obsidian

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(any time)  User types intent under "## ✍️ Your note" in the vault note
                        ↓
+≤15 min    vault-feedback.ts runs (launchd, every 15 min;
            export-obsidian also scans right before rendering)
                        ↓
            Match file → note via selene_id frontmatter
            INSERT INTO facts.note_feedback (precious, deduped)
            Re-pend note (note_state.status → 'pending')
                        ↓
+~5 min     process-llm.ts re-derives with the intent in-prompt
            applied_at stamped (only if extraction parsed)
                        ↓
+≤1 hour    export-obsidian.ts re-renders the note —
            feedback now a blockquote "— applied YYYY-MM-DD ✓"
            ✓ Status: Feedback applied

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+midnight  daily-summary.ts runs
                        ↓
            SELECT all notes from today
            Ollama: generate insight summary
            INSERT INTO daily_summaries
            ✓ Status: Summary ready

T+6am       send-digest.ts runs
                        ↓
            SELECT today's daily_summaries entry
            WRITE to pinned Apple Note "Selene Daily Digest"
            ✓ Status: Delivered
```

---

## 3. Agent Layer Flow

```
┌──────────────────────────────────────────────────────────────┐
│           agent-manager.ts (runs every 15 min)               │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Step 1: Load enabled agents from agent_registry             │
│  SELECT * FROM agent_registry WHERE enabled = 1              │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Step 2: For each agent — fetch relevant context             │
│                                                               │
│  e.g., Things Enricher:                                      │
│    - Unprocessed Things tasks without Selene context         │
│    - Recent processed notes with matching concepts           │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Step 3: Ollama reasoning                                    │
│                                                               │
│  Prompt: "Given these tasks and notes, propose enrichments.  │
│  Respond with JSON only: { actions: [...] }"                 │
│                                                               │
│  Allowed action_types are hardcoded per agent (closed        │
│  vocabulary — LLM cannot invent new action types)            │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Step 4: Insert proposed actions                             │
│                                                               │
│  INSERT INTO agent_jobs (agent_name, status="pending_review")│
│  INSERT INTO agent_actions (job_id, action_type, payload)    │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Step 5: Export reports for human review                     │
│                                                               │
│  → Apple Notes: "Selene Agent Report" (proposed actions)     │
│  → Obsidian: vault/agent-dashboard.md                        │
└──────────────────────────────────────────────────────────────┘
                            ↓
                  ┌─────────────────────┐
                  │  User reviews and   │
                  │  approves via       │
                  │  dashboard or Notes │
                  └─────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  Step 6: ActionExecutor runs approved actions                │
│                                                               │
│  UPDATE agent_actions SET status = "approved"                │
│  Run deterministic process code for each action_type        │
│  INSERT INTO action_execution_log (result, executed_at)      │
└──────────────────────────────────────────────────────────────┘
```

**Key contract:** Agents only *propose*. Nothing executes without explicit approval.
Approved actions run through deterministic code — the LLM only drives the reasoning step.

---

## 4. Data Model (Current)

```
┌─────────────────┐
│   raw_notes     │  ← Original captured content
│─────────────────│
│ id (TEXT PK)    │
│ title           │
│ content         │
│ created_at      │
│ content_hash    │  ← Duplicate detection
│ source          │  ← drafts | voice | eink
│ test_run        │  ← Marks test data
└─────────────────┘
         │
         │ 1:1
         ↓
┌─────────────────┐
│processed_notes  │  ← LLM extracted metadata
│─────────────────│
│ id (PK)         │
│ raw_note_id (FK)│
│ concepts        │  ← JSON array
│ primary_theme   │
│ energy_level    │
│ sentiment       │
│ essence         │  ← 1-sentence distillation
│ exported_at     │  ← Set when written to Obsidian
└─────────────────┘
         │
         │ 1:1
         ↓
┌─────────────────┐
│ daily_summaries │  ← Daily insight records
│─────────────────│
│ id (PK)         │
│ date            │
│ summary_text    │
│ note_count      │
│ sent_at         │  ← Set when delivered to Apple Notes
└─────────────────┘


AGENT LAYER TABLES
──────────────────

┌─────────────────────┐
│   agent_registry    │  ← Agent config (enable/disable without deployment)
│─────────────────────│
│ agent_name (PK)     │
│ description         │
│ schedule            │  ← cron expression
│ allowed_action_types│  ← JSON array (closed vocabulary)
│ enabled             │
│ last_run_at         │
│ config              │  ← JSON, agent-specific
└─────────────────────┘
         │
         │ 1:N
         ↓
┌─────────────────────┐
│    agent_jobs       │  ← One job per agent run
│─────────────────────│
│ id (PK)             │
│ agent_name (FK)     │
│ status              │  ← pending_review | approved | rejected | executed
│ context_snapshot    │  ← JSON, what the agent saw
│ created_at          │
└─────────────────────┘
         │
         │ 1:N
         ↓
┌─────────────────────┐
│   agent_actions     │  ← Individual proposed actions within a job
│─────────────────────│
│ id (PK)             │
│ job_id (FK)         │
│ action_type         │  ← Enum value from allowed_action_types
│ payload             │  ← JSON
│ status              │  ← proposed | approved | rejected | executed
└─────────────────────┘
         │
         │ 1:1
         ↓
┌──────────────────────────┐
│  action_execution_log    │  ← Audit trail of executed actions
│──────────────────────────│
│ id (PK)                  │
│ action_id (FK)           │
│ executed_at              │
│ result                   │  ← JSON
│ success                  │
└──────────────────────────┘
```

---

## 5. Deployment / Release Topology (prod/dev split — live 2026-05-29)

Code is edited in a dev sandbox and runs in production as a compiled, frozen
artifact. A launchd watcher auto-deploys on merge to `main`, build-gated.

```
┌────────────────────────────────────────────────────────────────────────────┐
│  DEV   ~/selene  (branch: main)                                              │
│    edit source · ts-node · port 5679 (manual) · dev DB ~/selene-data-dev     │
│    scratch vault · NO scheduled launchd agents                               │
└────────────────────────────────────────────────────────────────────────────┘
            │  merge PR / push  →  origin/main moves
            ↓
┌────────────────────────────────────────────────────────────────────────────┐
│  com.selene.prod.deploy-watcher   (launchd · StartInterval 300s = every 5m)  │
│    git fetch; origin/main sha == ~/selene-prod/.deployed-sha ?               │
│       same  → "up to date" (no-op)                                           │
│       moved → run deploy-prod.sh ↓                                            │
└────────────────────────────────────────────────────────────────────────────┘
            ↓
┌────────────────────────────────────────────────────────────────────────────┐
│  BUILD  ~/selene-build  (scratch clone — never hand-edited)                  │
│    reset --hard origin/main → npm install → npm run build (tsc)              │
│    ─── build FAILS → notify "deploy FAILED"; prod left untouched (THE GATE)  │
└────────────────────────────────────────────────────────────────────────────┘
            │  build OK
            ↓
┌────────────────────────────────────────────────────────────────────────────┐
│  PROD  ~/selene-prod  (compiled dist/ · real DB · iCloud vault · port 5678)  │
│    archive old dist → releases/<old-sha>/                                    │
│    rsync dist/  (EXCLUDES .env)  ·  npm install --omit=dev                    │
│    restart in place: launchctl kickstart -k com.selene.prod.*  (NOT bootout) │
│    health-check :5678 → write .deployed-sha → notify "deployed <sha>"        │
│    11 scheduled agents: com.selene.prod.{server, process-llm, …}             │
└────────────────────────────────────────────────────────────────────────────┘

Rollback:   ./scripts/rollback-prod.sh [sha]  → swap dist/ to releases/<sha>/,
            kickstart agents in place, health-check, notify.
Cutover / agent-set changes:  ./scripts/install-prod.sh  (interactive ONLY —
            generates + bootstraps prod plists from canonical launchd/*.plist;
            never run from the launchd watcher).
```

The capture → process → deliver flows in sections 1–3 are **identical** in dev
and prod — only the runtime (ts-node vs compiled `dist/`), DB, vault, port, and
launchd label prefix (`com.selene.*` → `com.selene.prod.*`) differ.

---

*These diagrams reflect the system as of 2026-06-11. For historical architecture
(embedding pipeline, thread detection, LanceDB), see the archived design docs in
`docs/plans/_archived/` and `archive/shelved-2026-03-21/`.*
