# Agent Enrichments

**What this does for you:** A background agent looks at your Things tasks that are missing tags or notes, cross-references your Selene note archive, and proposes tags and context notes for you to approve — so your tasks get organized without you having to think about it.

## Using it

The agent never changes your Things tasks on its own. It *proposes*, you *approve*, and only then does anything get written. There are two halves to your day-to-day flow.

### 1. Ask for suggestions

The thing that actually reads your tasks and comes up with suggestions only runs when you start it. From the project folder, run:

```bash
npx ts-node src/agents/things-metadata-enricher.ts "Inbox"
```

Replace `"Inbox"` with the name of the Things project you want enriched. The agent pulls the tasks from that project that are missing notes or tags, asks the local LLM for suggestions, and saves them as proposed actions waiting for your review. It does **not** touch Things yet.

> **Worth knowing:** this step is manual today. There is a scheduled background job (see *How it works*), but that job only *delivers* and *nudges* — it does not generate new suggestions. If you want fresh suggestions, you run the command above.

### 2. Review and approve in the dashboard

Open the dashboard in your browser:

```
http://localhost:5678/dashboard
```

It has four pages, linked across the top:

- **Home** (`/dashboard`) — a quick count of how many actions are awaiting your approval and how many jobs are paused, plus a list of registered agents and when each last ran.
- **Approval Queue** (`/dashboard/queue`) — the important one. Each proposed change shows what it is (add a tag, add a context note), which task it applies to, the agent's reasoning, and a confidence percentage. Two buttons: **Approve** or **Reject**.
- **Reports** (`/dashboard/reports`) — a readable summary of each agent run.
- **Agents** (`/dashboard/agents`) — a table where you can **Enable** or **Disable** an agent.

When you click **Approve**, Selene actually writes the change into Things for you (the tag gets added or the note gets filled in). **Reject** discards the suggestion and nothing happens to the task.

### 3. Where reports also show up

Even if you don't open the dashboard, every agent run produces a report that gets delivered to:

- **Apple Notes** — a note named `Selene Agent: Things Metadata Enricher` (new runs are appended).
- **Obsidian** — a file in your vault under `agent-reports/`.

And if proposed actions sit unreviewed for more than 4 hours, you get a macOS notification reminding you that something needs your approval.

## How it works

### The agent components

- **`src/agents/base-agent.ts`** — the `BaseAgent` class all agents extend. It defines the run cycle: `collect()` gathers data, `reason()` produces proposed actions, and `run()` saves them, writes a report, and pauses the job to wait for your approval.
- **`src/agents/things-metadata-enricher.ts`** — the `ThingsMetadataEnricher`, the only agent that exists today. It reads tasks from a Things project (via `src/lib/things.ts`, which uses AppleScript), finds tasks missing notes or tags, searches your Selene note archive for related notes, and asks the local Ollama LLM to suggest 1-3 tags and a one-sentence context note. Its allowed actions are `things.update_notes` and `things.add_tag`.
- **`src/agents/executor.ts`** — the `ActionExecutor`. When you approve an action, this is what actually carries it out. The `thingsExecutor` singleton has handlers registered for `things.update_notes` and `things.add_tag`, both of which call into `src/lib/things.ts` to write to Things via AppleScript.
- **`src/routes/dashboard.ts`** — the four dashboard pages (HTML, served by the Fastify server).
- **`src/routes/agents.ts`** — the API behind the dashboard buttons. Approving an action (`POST /agents/actions/:id/approve`) marks it approved and immediately runs it through the executor.

### The SQLite tables

Four tables, all created by `runAgentMigrations()` in `src/lib/agent-db.ts`:

- **`agent_registry`** — the list of known agents, whether each is enabled, and when it last ran.
- **`agent_jobs`** — one row per agent run, with a status (`running`, `paused`, `complete`, `error`).
- **`agent_actions`** — the individual proposed changes, with a status (`pending`, `approved`, `rejected`, `executing`, `done`).
- **`agent_reports`** — the markdown summary for each run and which channels it's been delivered to.

### The schedule and the launchd agent

- **launchd agent:** `com.selene.agent-manager` (`launchd/com.selene.agent-manager.plist`)
- **Runs:** every **15 minutes** (`StartInterval` of `900` seconds). It is *not* tied to a specific time of day.
- **What it runs:** `scripts/selene-agent-manager`, which executes `src/workflows/agent-manager.ts`.

Important: the scheduled job runs `agent-manager.ts`, and that script does only three things — registers the known agents in the database, delivers any undelivered reports to Apple Notes and Obsidian, and sends escalation notifications for actions paused over 4 hours. **It does not generate new suggestions.** Generating suggestions is the manual step in *Using it*.

(You may notice each agent stores a `schedule` value like `0 */4 * * *` in the registry. That value is descriptive metadata only — nothing reads it to trigger runs.)

### Delivery targets

- **Apple Notes** and **Obsidian** — handled by `deliverPendingReports()` in `src/workflows/agent-manager.ts`. Obsidian reports are written to `<vault>/agent-reports/<date>-<agent-name>.md`.
- **macOS notification** — only on escalation (a paused job older than 4 hours).

## Configure & customize

| Knob | How |
|------|-----|
| **Which Things project gets enriched** | Pass it as the argument to the enricher: `npx ts-node src/agents/things-metadata-enricher.ts "Project Name"`. The scheduled delivery job uses the `THINGS_ENRICHER_PROJECT` env var (default `Inbox`), set in `launchd/com.selene.agent-manager.plist`. |
| **Enable / disable an agent** | Use the **Agents** page in the dashboard, or `curl -X POST http://localhost:5678/agents/things-metadata-enricher/disable` (and `.../enable`). |
| **How often the delivery job runs** | Edit `StartInterval` (seconds) in `launchd/com.selene.agent-manager.plist`, then reinstall with `./scripts/install-launchd.sh`. Default is `900` (15 minutes). |
| **Escalation timing** | The 4-hour threshold is the `ESCALATION_THRESHOLD_MS` constant in `src/workflows/agent-manager.ts`. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No suggestions appear in the Approval Queue | The enricher only runs when you start it. Run `npx ts-node src/agents/things-metadata-enricher.ts "Inbox"` and refresh `/dashboard/queue`. |
| The command runs but proposes nothing | The agent only looks at tasks missing notes *or* tags. If every task in the project is already filled in, there's nothing to propose. Try a different project name. |
| Dashboard pages won't load | The dashboard is served by the Selene server. Check it's running: `curl http://localhost:5678/health`. Restart with `launchctl kickstart -k gui/$(id -u)/com.selene.server`. |
| Approved a change but Things didn't update | Approval writes to Things via AppleScript. Make sure the Things app is installed and running. Check the server log for `Action execution failed`: `tail -f logs/server.out.log`. A failed action is reverted to `approved` so you can retry it by approving again. |
| Reports aren't reaching Apple Notes or Obsidian | The every-15-minute delivery job handles this. Run it manually to test: `npx ts-node src/workflows/agent-manager.ts`. Then check `logs/agent-manager.log` and `logs/agent-manager.error.log`. |
| Want to see what's queued without the dashboard | `curl http://localhost:5678/agents/status` for counts, or `curl http://localhost:5678/agents/actions/pending` for the full list. |
| Inspect the raw data | `sqlite3 data/selene.db "SELECT status, COUNT(*) FROM agent_actions GROUP BY status;"` |

## Related

- **Design doc:** `docs/plans/2026-05-23-agent-layer-design.md` (and the plans `docs/plans/2026-05-23-agent-layer-plan.md`, `docs/plans/2026-05-24-agent-layer-plan.md`). Note: the design doc describes a fully autonomous, twice-daily schedule; the actual implementation runs delivery every 15 minutes and requires you to start the enricher manually.
- **Connected guides:**
  - `docs/guides/features/capturing-notes.md` — how notes get into the archive the agent searches.
  - `docs/guides/features/obsidian-library.md` — your Obsidian vault, where agent reports also land.
  - `docs/guides/features/daily-digest.md` — the other Apple Notes delivery you receive.

---
*Last updated: 2026-05-25*
