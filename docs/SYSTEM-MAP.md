# Selene System Map

> **The live, zoomable index of Selene.** The workflow table below is
> **generated** from `src/workflows/*.ts` + `launchd/*.plist` — do not hand-edit
> between the markers. Everything outside the markers is hand-written meaning.
>
> Zoom: **[CLAUDE.md](../CLAUDE.md)** (what & where) → **this file** (the inventory)
> → **[block diagrams](backend-block-diagrams.md)** + the workflow source (deep detail).

## How Selene flows

Capture (Drafts / eink / voice → `raw_notes`) → Process (LLM extraction, essences,
synthesis) → Browse / Deliver (Obsidian vault, Apple Notes digest, worksheets, Folio).
See the [block diagrams](backend-block-diagrams.md) for the full picture.

## Workflows (generated)

<!-- GENERATED:workflows START -->
| Workflow | Schedule | Reads | Writes | Purpose |
|---|---|---|---|---|
| [agent-manager](../src/workflows/agent-manager.ts) | every 15 min | agent_jobs, agent_reports | agent_reports (delivery state), Apple Notes, Obsidian vault | Run background agents, deliver their pending reports, and escalate stale approvals |
| [daily-summary](../src/workflows/daily-summary.ts) | daily 00:00 | raw_notes, processed_notes | Obsidian vault (daily summary), digest .txt file | LLM-summarize the past week's notes into an Obsidian daily note plus a condensed digest file |
| [distill-essences](../src/workflows/distill-essences.ts) | every 5 min | processed_notes, raw_notes, note_feedback | processed_notes | Backfill/retry LLM essences for processed notes that still lack one |
| [eink-ingest](../src/workflows/eink-ingest.ts) | every 30 min | eink watch directory (PDFs) | raw_notes (via ingest), eink archive + manifest | OCR handwritten Kindle Scribe PDFs (Ollama vision) and ingest each as a note |
| [export-obsidian](../src/workflows/export-obsidian.ts) | hourly | raw_notes, processed_notes, topic_clusters | Obsidian vault, raw_notes (export hash) | Render processed notes into an Obsidian vault — note files, LLM Maps-of-Content & dashboard |
| [folio-feedback](../src/workflows/folio-feedback.ts) | every 5 min | raw_notes, processed_notes | Folio project feedback files, note_state (status_folio) | Write Kindle-Scribe annotations back as markdown feedback files in each Folio project repo |
| [generate-worksheet](../src/workflows/generate-worksheet.ts) | server routes (GET /api/worksheets/today, POST /api/worksheets/:id/answers) | raw_notes (via injected route deps) | raw_notes (new notes, via injected route deps) | Build the daily review worksheet and apply its answers (capture/acknowledge) for the iPad |
| [ingest](../src/workflows/ingest.ts) | webhook (POST /webhook/api/drafts); also called directly by eink-ingest & voice-ingest | raw_notes (dedup) | raw_notes | Capture a note — dedupe by content hash, store it, link a calendar event |
| [process-llm](../src/workflows/process-llm.ts) | every 5 min | raw_notes, note_feedback | processed_notes, note_embeddings, note_connections, note_feedback | LLM-extract concepts/themes/category from pending notes, plus essence, embedding & connections |
| [send-digest](../src/workflows/send-digest.ts) | daily 06:00 | digest .txt file, topic_clusters | Apple Notes, TRMNL | Deliver the daily digest (plus synthesis sections) to the "Selene Daily" Apple Note and TRMNL |
| [synthesize-topics](../src/workflows/synthesize-topics.ts) | daily 02:00 | raw_notes, processed_notes | topic_clusters, topic_note_links, synthesis_meta | Group processed notes into the 8 category clusters and LLM-synthesize each topic + evolution |
| [vault-feedback](../src/workflows/vault-feedback.ts) | every 15 min | Obsidian vault, raw_notes, processed_notes | note_feedback (facts.db), note_state | Scan vault "Your note" sections → ingest author intent into facts.note_feedback + re-pend notes for re-derivation |
| [voice-ingest](../src/workflows/voice-ingest.ts) | every 30 min | Apple Voice Memos library, voice_transcriptions | raw_notes (via ingest), voice_transcriptions, voice-memo archive | Transcribe Apple Voice Memos with Whisper and ingest each as a note |
<!-- GENERATED:workflows END -->

## Regenerating

```bash
npx ts-node scripts/gen-system-map.ts          # rewrite the table
npx ts-node scripts/gen-system-map.ts --check  # CI / hook drift check
```
