---
name: diagram-sync
description: Update docs/backend-block-diagrams.md to match the current set of workflows, launchd agents, and data flows. Use when the Stop hook warns that workflow or launchd files changed this session, or any time workflow inventory changes.
---

# Diagram Sync

Keeps `docs/backend-block-diagrams.md` in sync with the actual running system after workflows or launchd agents change.

## When to invoke

- **Automatically by Stop hook**: "Update docs/backend-block-diagrams.md to reflect current system"
- **After `/new-workflow`**: scaffolds files but doesn't update the diagram
- **After archiving a workflow**: the removed workflow's box must be deleted from the diagram
- **After a schedule change**: plist `StartInterval` changed → the diagram interval label must match

## Procedure

1. **Read the current diagram**:
   ```
   docs/backend-block-diagrams.md
   ```

2. **Build ground-truth inventory** from three authoritative sources:
   ```bash
   # Active workflow scripts (exclude test files)
   ls src/workflows/*.ts | grep -v '\.test\.ts'

   # What's actually installed and running
   launchctl list | grep selene

   # Schedule intervals from plists
   grep -E 'StartInterval|StartCalendarInterval|KeepAlive' launchd/*.plist
   ```

3. **Diff** inventory against the diagram sections:
   - **Capture layer**: each ingest source box (Drafts, eink-ingest, voice-ingest) has a running agent
   - **Processing layer**: each scheduled box matches a real workflow with the correct interval label
   - **Delivery layer**: export-obsidian, daily-summary, send-digest boxes match real workflows
   - **Arrow labels**: `→ INSERT INTO <table>` and `→ UPDATE <table>` match actual DB writes

4. **Make targeted edits** — change only the boxes and labels that are out of sync. Do NOT rewrite the entire diagram. ASCII art diffs badly; surgical changes are safer.

5. **Update the `Last Updated:` date** at the top of the file.

## What NOT to change

- Diagram formatting: box widths, padding, box-drawing characters (`┌─┐│└┘↓→`) — intentional style
- `(always running, port 5678)` annotation on the Fastify server — reflects `KeepAlive` in plist, not `StartInterval`
- The Selene/Folio boundary — Folio is a **separate repo** (`~/folio`); its blocks appear only at the ingestion seam, not as internal components

## Common scenarios

| What changed | What to update in diagram |
|---|---|
| New workflow added | Add box to appropriate layer; add schedule label |
| Workflow archived | Remove its box; verify no arrows point to it |
| Schedule changed (e.g., hourly → 30 min) | Update `Every X min:` / `Hourly:` / `Daily at Xam:` label |
| New DB table written | Update `→ INSERT INTO <table>` arrow label in that box |
| New capture source added | Add source box + arrow into ingest flow |
| Workflow renamed | Update box title and all cross-references in arrow labels |
