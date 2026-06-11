# Obsidian Feedback ("Your note")

**What this does for you:** when Selene files a note wrong, you type what you actually meant directly under the note in Obsidian — Selene re-files it with your words as context and shows a ✓ when done. Your words are kept forever and shape every future re-derivation of that note.

## Using it

1. While browsing the vault (Mac or iPad — the vault is iCloud-synced, so mid-ExcaliBrain-flythrough on the iPad works), open any exported note. Every one ends with a `## ✍️ Your note` section.
2. Type plain text under that heading — free-text intent, "what I actually meant," not a category name. Example: *"This is actually about a skill I possess and enjoy using — remember it as a personal strength."*
3. That's it. Selene picks it up automatically:
   - your note gets re-filed (category, concepts, theme, essence re-derived with your statement weighted over the surface topic),
   - your text moves into a blockquote in the same section, stamped `> — applied YYYY-MM-DD ✓`.
4. **Timing:** worst case about 1 hour 20 minutes before the ✓ appears — up to 15 min for the scan to pick it up, ~5 min for re-processing, then up to an hour for the next hourly export (top of each hour) to rewrite the file. Often much faster.

**The protocol, in one line:** blockquoted lines (`>`) in the section are Selene's applied history; anything in plain text is new feedback. So don't write feedback as a `>` quote — it would be treated as history and ignored.

You can leave feedback on the same note more than once; each round is kept and all of them ride along on every future re-derivation.

## How it works

The loop (Phase 1 of the design):

```
You type under ## ✍️ Your note
        ↓ every 15 min (or right before any export)
vault-feedback scan: src/workflows/vault-feedback.ts
  parse section → plain text = new feedback
  match file → note via selene_id: frontmatter
        ↓ one transaction
INSERT INTO facts.note_feedback  (precious — survives rebuild)
  + snapshot of the filing being corrected (original_filing)
  + re-pend the note (note_state.status → 'pending')
        ↓ every 5 min
process-llm re-derives the note with your intent injected into the
  extraction prompt ("Weight the author's stated intent over the
  surface topic...") and the essence prompt (distill-essences retries too)
  → applied_at stamped ONLY if extraction actually parsed
        ↓ hourly
export-obsidian re-renders the note: applied feedback becomes the
  blockquoted ✓ history in the Your-note section
```

Key properties, all verified in code:

- **Identity** — every exported note carries `selene_id: <n>` in its frontmatter (`src/lib/obsidian-render.ts`). Hand-made files without it (or with an id Selene doesn't know) are skipped and logged as `unmatched`, never touched.
- **Durable by construction** — feedback lives in `facts.note_feedback` (the precious, Time-Machine-backed side of the fact-store split). A full `rebuild` wipes derived data but not your words; every future re-derivation re-injects them via `getIntentTexts` (`src/lib/vault-feedback.ts`).
- **Deduped** — a UNIQUE index on (note, text) makes rescans idempotent; the same text is never ingested or applied twice.
- **Honest ✓** — `applied_at` is stamped only when the LLM extraction parsed (`src/workflows/process-llm.ts`). If Ollama returned garbage and the note degraded to defaults, your feedback stays visibly pending (plain text) and is retried implicitly on the next loop.
- **Words never lost** — the exporter's preserve-on-render passthrough: when rewriting a note file, any un-ingested plain text in the Your-note section is re-appended verbatim, so no export/scan ordering can clobber it. The hourly export additionally runs the scan *immediately before* rewriting files (scan-before-clobber, `src/workflows/export-obsidian.ts`). The one residual caveat is a cross-device iCloud sync race (you type on the iPad in the same instant the Mac rewrites that file before iCloud delivered your edit); it's narrow, and if iCloud produces a conflict copy, that copy still has the `selene_id` frontmatter and ingests on the next scan as the backstop.

Schedules: `launchd/com.selene.vault-feedback.plist` (`StartInterval` 900 = every 15 min), `launchd/com.selene.export-obsidian.plist` (top of every hour), process-llm/distill-essences every 5 min.

## Configure & customize

- **Scan frequency:** `StartInterval` in `launchd/com.selene.vault-feedback.plist` (seconds; 900 = 15 min). Re-install agents after editing.
- **Run a scan now:** `npx ts-node src/workflows/vault-feedback.ts` — prints JSON counts (`scanned / ingested / duplicates / unmatched / errors`).
- **Logs:** `logs/vault-feedback.log` and `logs/vault-feedback.error.log` (dev paths; under `~/selene-prod/logs/` for the prod agent once installed). The hourly export also logs its pre-export scan in `logs/export-obsidian.log`.
- **Vault location:** `SELENE_VAULT_PATH` in the plists (prod: the iCloud Obsidian vault). The scanner reads `<vault>/Notes/*.md` only.

### Rollout note (one-time)

The launchd agent is **new**, and `deploy-prod.sh` only restarts *existing* agents — after this branch merges and deploys, run `./scripts/install-prod.sh` once to load `com.selene.prod.vault-feedback`. Also expect the first export after deploy to rewrite the full corpus once: the new `selene_id` frontmatter + Your-note section change every note's content hash (the export's write cap spreads this over a few hourly runs).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| "My text disappeared" | Look again — it almost certainly moved *into* the section as a `>` blockquote ending `— applied ... ✓`. That's the loop closing, not a loss. Genuinely lost text is near-impossible (preserve-on-render passthrough); the only window is the cross-device iCloud race above, and a conflict copy still ingests. |
| No ✓ after ~1.5 hours | Check `logs/vault-feedback.error.log` and run the scan manually (`npx ts-node src/workflows/vault-feedback.ts`) — is your note counted as `unmatched`? Then the file lacks `selene_id:` frontmatter (hand-made files are skipped by design). Otherwise: is Ollama up (`curl http://localhost:11434/api/tags`)? Is there a pending backlog (`selene-inspect counts`)? |
| Feedback shows ✓ but the filing didn't change much | The LLM may legitimately land on a similar filing. Your intent is permanent context now — it rides along on *every* future derivation (including rebuilds), so it still compounds. If extraction degraded (parse failure), the text stays plain/pending and re-runs next cycle instead of falsely showing ✓. |
| "I typed my feedback as a `>` quote" | Blockquotes are reserved for Selene's applied history — the parser ignores them. Rewrite it as plain text under the heading. |
| Scan exits non-zero | Per-file errors; `logs/vault-feedback.error.log` carries `errorSamples` (filename + message, never note content). |

## Related

- Design doc: `docs/plans/2026-06-10-obsidian-feedback-loop-design.md` (Phase 2 — few-shot corrections in the classification prompt — is gated on data from this phase)
- Plan: `docs/plans/2026-06-10-obsidian-feedback-loop-plan.md`
- Connected guides: `docs/guides/features/knowledge-constellation.md` (the ExcaliBrain browse you'll be mid-flight in), `docs/guides/features/obsidian-library.md`, `docs/guides/features/synthesis-layer.md`, `docs/guides/features/releases.md` (deploy + the install-prod note above)

---
*Last updated: 2026-06-11*
