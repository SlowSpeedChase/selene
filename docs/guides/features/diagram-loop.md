# Diagram Loop (iPad ⇄ Repo)

**What this does for you:** lets you think about how Selene works/should work by **drawing on your iPad in Apple Freeform**, then hands those drawings to Claude — which reads them and turns them into design docs, plans, and committed diagrams in the repo.

## Using it

A "lap" of the loop:

1. **Get a starting picture.** Ask Claude to render the seed, or run it yourself:
   ```bash
   npx ts-node scripts/render-seed-diagram.ts
   ```
   This drops `seed-system-architecture-overview.png` into **iCloud Drive › Selene-Diagrams** (visible in the iPad Files app within a minute). It's the *current* system, drawn from the up-to-date docs.
2. **Draw.** On iPad, open **Freeform** → new board → insert the seed image (Files → iCloud Drive → Selene-Diagrams) → mark it up with the Apple Pencil. Sketch what should change, circle, annotate, redraw.
3. **Export.** Share-sheet → **Save to Files → Selene-Diagrams**. (One tap. Don't worry about the filename.)
4. **Hand it to Claude.** Say *"new diagram"* (or *"I exported a drawing"*). Claude reads the newest export, tells you what it understood, and — when it's a keeper — files it in `docs/diagrams/` and commits.

You can stay on the same Freeform board across laps; you only re-insert a seed when you want a fresh current-system starting point.

## How it works

- **The bridge is iCloud Drive**, the one folder both your iPad and the Mac can see: `~/Library/Mobile Documents/com~apple~CloudDocs/Selene-Diagrams/`. Drawings are **deliberately not** routed through the Obsidian vault (that's a protected store of your real notes).
- **Claude reads PNGs directly.** No OCR pipeline — the `Read` tool renders images visually, so a hand-drawn board is something Claude genuinely sees.
- **The seed is always current.** `scripts/render-seed-diagram.ts` first runs `gen-system-map.ts --check` and **aborts if `SYSTEM-MAP.md` is stale**, then renders the ASCII architecture from `docs/backend-block-diagrams.md` to PNG via a headless browser (puppeteer). The pure markdown→HTML core lives in `src/lib/seed-diagram.ts` (unit-tested in `src/lib/seed-diagram.test.ts`).
- **Keepers live in the repo.** Each saved diagram is a pair in `docs/diagrams/`: `<topic>.png` (the drawing) + `<topic>.md` (Claude's reading + links), indexed in `docs/diagrams/README.md`.
- **Overwrite, never accumulate.** Re-drawing a topic overwrites the same files in place; **git history is the version store**. The iCloud inbox is transient — Claude clears processed exports after capture (the reusable seed is kept).
- **No daemon.** There's no background watcher; Claude does the capture + commit during a lap.

## Configure & customize

| Knob | Where | How |
|------|-------|-----|
| Which diagram to seed from | `scripts/render-seed-diagram.ts` arg | `npx ts-node scripts/render-seed-diagram.ts "Note Lifecycle Timeline"` — renders a different `## ` section of `backend-block-diagrams.md` |
| iCloud inbox location | `scripts/render-seed-diagram.ts` (`INBOX`) | Edit the path constant if you move the folder |
| Seed source doc | `scripts/render-seed-diagram.ts` (`SOURCE`) | Defaults to `docs/backend-block-diagrams.md` |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Seed script aborts: "SYSTEM-MAP.md is OUT OF DATE" | The system docs drifted. Run `npx ts-node scripts/gen-system-map.ts`, then re-sync `docs/backend-block-diagrams.md` (the `diagram-sync` skill), commit, and re-run the seed. |
| Seed PNG doesn't appear on iPad | iCloud sync lag — wait a moment, or open the Files app to nudge it. Confirm it exists on the Mac: `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/Selene-Diagrams/`. |
| Claude grabbed the wrong export | Exports are picked newest-first (excluding `seed-*`). Re-export the one you want so it's newest, or tell Claude the filename. |
| Drawing copies piling up in the inbox | Expected to be cleared on capture; if not, Claude can `find … -name '*.png' ! -name 'seed-*' -delete` after confirming keepers are committed. |

## Related

- Design doc: `docs/plans/2026-06-08-freeform-diagram-loop-design.md`
- Plan: `docs/plans/2026-06-08-freeform-diagram-loop-plan.md`
- Diagram store + index: `docs/diagrams/README.md`
- Source-of-truth inventory the seed is anchored to: `docs/SYSTEM-MAP.md`

---
*Last updated: 2026-06-08*
