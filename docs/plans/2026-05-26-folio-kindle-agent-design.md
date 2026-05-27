# Folio Kindle Agent — MCP Server + Scheduled Digest

**Date:** 2026-05-26
**Status:** Vision
**Topic:** folio, kindle, mcp, agent, digest

---

## Vision

A scheduled Claude agent that reviews every document Folio serves, identifies what has changed since the last delivery, and sends a structured Kindle digest: executive summary → table of contents → full changed documents. Folio exposes its capabilities as an MCP server; Claude is the brain that reads, curates, and writes the summary.

---

## Design Principles

- **Delta-only:** Only send documents modified since the last delivery. No duplicates.
- **Claude as author:** The executive summary is written by Claude, not mistral:7b. Quality matters here.
- **Folio owns its log:** `logs/kindle-deliveries.json` is Folio's record — no Selene DB dependency.
- **Zero new delivery infrastructure:** Reuses existing `sendToKindle()` (nodemailer) and `generatePdf()` (Puppeteer).
- **On-demand + scheduled:** Same MCP tools work for both nightly launchd cron and manual invocation.

---

## Architecture

```
Scheduled Claude agent (nightly cron + on-demand)
          │
          │  MCP tools over stdio
          ▼
  Folio MCP Server  (folio/src/mcp.ts)
  ┌──────────────────────────────────────┐
  │  list_changed_documents              │
  │  read_document(path)                 │
  │  get_delivery_history                │
  │  send_kindle_digest(summary,toc,docs)│
  └──────────────────────────────────────┘
          │
          ▼
  Claude writes executive summary + ToC
          │
          ▼
  Puppeteer PDF → SMTP → Kindle
  folio/logs/kindle-deliveries.json updated
```

---

## MCP Tools

### `list_changed_documents`
Scans `projectDir` for `.md` and code files. Compares each file's `mtime` against the `sent_at` of the most recent entry in `kindle-deliveries.json`. Returns `{ path, mtime, size }[]` for all files newer than the cutoff. If no prior delivery exists (first run), returns all documents.

### `read_document(path)`
Returns raw file content (markdown as-is, code as plain text). Enforces path traversal safety — resolved path must stay within `projectDir`.

### `get_delivery_history`
Returns the last 5 entries from `kindle-deliveries.json`: timestamp, doc list, doc count, 200-char summary preview. Gives Claude context to write "since your last digest on Tuesday, 3 docs changed…"

### `send_kindle_digest(executive_summary, toc, docs[])`
Takes Claude-assembled content, generates a PDF (summary page → ToC page → full doc pages) via existing `generatePdf()`, sends via existing `sendToKindle()`, appends a record to `kindle-deliveries.json`. Only tool with side effects.

---

## Delivery Log

**`folio/logs/kindle-deliveries.json`** — append-only, gitignored:

```json
[
  {
    "id": "2026-05-26T09:00:00Z",
    "sent_at": "2026-05-26T09:00:00Z",
    "docs_included": ["CLAUDE.md", "docs/plans/INDEX.md"],
    "doc_count": 2,
    "summary_preview": "Two documents changed since May 24th. CLAUDE.md..."
  }
]
```

**First-run behavior:** If log is missing or empty, `list_changed_documents` returns all documents. The executive summary becomes a full project orientation rather than a delta.

**No-change behavior:** If `list_changed_documents` returns empty, the agent exits without calling `send_kindle_digest`. No empty digest sent.

---

## Scheduling

**Nightly (automatic):** Registered via `/schedule` as a Claude Code cron agent. Runs at a fixed time (e.g. 9am), calls the full tool chain, sends only if changes exist.

**On-demand:** From any Claude Code session: *"send today's Folio digest"* — same MCP tools, same flow, no separate command needed.

---

## MCP Registration

New entry in `.claude/settings.json` under `mcpServers`:

```json
"folio": {
  "command": "npx",
  "args": ["ts-node", "/Users/chaseeasterling/folio/src/mcp.ts"]
}
```

---

## What's New in Folio

- `src/mcp.ts` — MCP server (new file, ~150 lines)
- `logs/kindle-deliveries.json` — delivery log (created on first send, gitignored)
- `@modelcontextprotocol/sdk` added to `package.json`

No changes to existing Folio server, send, or PDF logic.

---

## Acceptance Criteria

- [ ] `list_changed_documents` returns correct delta vs. last delivery timestamp
- [ ] `read_document` rejects paths outside `projectDir`
- [ ] `send_kindle_digest` generates a PDF with summary → ToC → docs and emails to Kindle
- [ ] `kindle-deliveries.json` is updated after every successful send
- [ ] No digest sent when nothing has changed since last delivery
- [ ] First-run (no log) sends all documents
- [ ] MCP server registered in `.claude/settings.json` and callable from Claude Code
- [ ] Scheduled cron agent runs nightly, skips silently if no changes
- [ ] On-demand trigger works from a Claude Code session

---

## ADHD Check

- **Reduces friction:** Zero-configuration — point Claude at Folio, digest appears on Kindle
- **Externalizes cognition:** You don't have to remember what changed; the agent tracks it
- **Makes time visible:** "Since Tuesday, 3 docs changed" frames the delta against your schedule
- **Passive by default:** Nightly cron means review material arrives without you thinking about it

## Scope Check

Two discrete tracks, each under 2 days:
- **Track A (Folio):** `src/mcp.ts` + `package.json` dependency + `.gitignore` entry
- **Track B (Claude Code):** MCP registration in settings + scheduled agent prompt

Total: ~1 week or less.
