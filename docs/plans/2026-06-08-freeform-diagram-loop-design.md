# Freeform ⇄ Repo Visual Thinking Loop

**Date:** 2026-06-08
**Status:** Ready
**Topic:** ipad, apple-pencil, freeform, diagrams, visual-thinking, feedback-loop

---

## Problem

The user is a visual thinker and wants an **ongoing medium** for thinking about how
Selene should work — sketching on iPad with Apple Pencil — that *continuously flows
into the repo* so Claude can read the drawings and turn them into design docs/plans,
and so the work is preserved. The starting point must be **existing repo documents**,
not a blank canvas.

Today the only "diagrams" in the repo are ASCII/markdown text
(`docs/SYSTEM-MAP.md`, `docs/backend-block-diagrams.md`) — drift-proof, but not a
medium a visual thinker wants to *design* in.

## Key Realization

Claude's `Read` tool renders PNG/JPG **visually**. So if a hand-drawn diagram lands in
the repo as an image, Claude can genuinely see and interpret it — **no OCR pipeline
required**. The whole loop reduces to: get a PNG into a place Claude looks, and write
something useful back.

## Decisions (from brainstorming)

| Question | Decision | Why |
|---|---|---|
| Goal | **Ongoing visual thinking medium** | Not a one-off; iPad becomes the default place to think about Selene |
| Drawing app | **Apple Freeform** | Best Pencil feel; user accepts its trade-offs |
| Lock-in | **Accepted** — Freeform boards are sealed (proprietary iCloud container, no file on disk). Only the share-sheet PNG/PDF export leaves. Claude cannot read the live board or write *into* Freeform. | User values the drawing feel over round-trip editability |
| Loop direction | **One-and-a-half-way** | Editable master stays in Freeform; repo gets flattened PNG snapshots; Claude gives back docs/plans (+ optional PNG to re-import) |
| Bridge | **iCloud Drive folder** (the only filesystem both iPad and Mac share) — **not** the Obsidian vault | Vault is a guarded prod surface (`prod-data-guard` blocks it). Diagrams stay clear of real notes. |
| Seed source | **Generated `SYSTEM-MAP.md`, via a refreshed `backend-block-diagrams.md`** (Option C) | The seed must be anchored to the drift-proof source so "start from existing docs" never means "start from a stale picture" |

## Architecture

### The bridge
- **iCloud inbox:** `~/Library/Mobile Documents/com~apple~CloudDocs/Selene-Diagrams/`
  (Files app → iCloud Drive → `Selene-Diagrams`). Freeform "Save to Files" writes here;
  the Mac reads here.
- **Repo home:** `docs/diagrams/` (git-versioned) — where *keeper* diagrams + Claude's
  interpretations live permanently.

### The lap
```
  SEED   Claude renders the current system (from SYSTEM-MAP-aligned
         backend-block-diagrams.md) → PNG into the iCloud inbox.
         User opens Freeform, "add image", draws on top.
    │
  DRAW   User sketches. Share-sheet → Save to Files → Selene-Diagrams.   (1 tap)
    │
  READ   User says "new diagram" (or Claude checks the inbox). Claude
         Reads the newest PNG by mtime and writes back what it understood.
    │
  GIVE   • a design doc / plan in docs/plans/   (the usual give-back)
   BACK  • the keeper PNG copied into docs/diagrams/ + an interpretation
           note (<topic>.md) next to it, then committed to git
         • (optional) Claude renders a cleaned PNG back into the inbox →
           user re-imports to draw on top.   (optional 2nd tap)
```

### Conventions
- **"Latest" = newest file by modified-time** in the inbox. No renaming required;
  lean on the filesystem's timestamps, not a brittle naming scheme.
- **Each keeper is a pair** in `docs/diagrams/`: `<topic>.png` + `<topic>.md`
  (Claude's reading + links to any design docs it spawned). A small
  `docs/diagrams/README.md` indexes them — a visual table of contents of the user's
  own thinking, diffable in git.
- **No new daemon.** Claude does the copy-into-repo + commit during a lap. A launchd
  watcher can be added later *only if* the manual step proves annoying.

### Seed correctness (Option C — the crux of "use the correct doc, kept updated")
Investigation found `backend-block-diagrams.md` was **stale**: missing 3 real
workflows (`folio-feedback`, `generate-worksheet`, `synthesize-topics`). It is
hand-maintained via a *reminder* that had already failed. By contrast
`SYSTEM-MAP.md` is **generated** by `scripts/gen-system-map.ts` with a pre-push
drift check — it cannot silently rot.

Therefore:
1. **One-time fix:** bring `backend-block-diagrams.md` back in line with
   `SYSTEM-MAP.md` (add the 3 missing workflows) via the `diagram-sync` skill.
2. **Standing rule:** the **seed step always regenerates/verifies against
   `SYSTEM-MAP.md` before rendering**, so every seed that reaches the iPad is
   verified-current. The seed can never start the user from a wrong picture.

## Acceptance Criteria
- [ ] `~/Library/Mobile Documents/com~apple~CloudDocs/Selene-Diagrams/` exists and is reachable from Freeform's "Save to Files".
- [ ] `docs/diagrams/` exists with a `README.md` index.
- [ ] `backend-block-diagrams.md` is current (3 missing workflows added; `gen-system-map.ts --check` passes for SYSTEM-MAP).
- [ ] A repeatable **seed step** renders the current system to a PNG in the iCloud inbox, after verifying against SYSTEM-MAP.
- [ ] One full lap demonstrated: user draws → exports → Claude reads the PNG → writes an interpretation `.md` + commits the keeper.

## ADHD Check
- **Reduces friction?** Yes — one export tap per lap; no naming rules; no new infra to babysit.
- **Visible?** Yes — turns text-only architecture into a visual medium the user actually wants to use.
- **Externalizes cognition?** Yes — drawings + interpretations are preserved and indexed in git, not held in the head.

## Scope Check
Well under a week: create two folders, refresh one doc (existing skill), write one
seed-render helper, document the loop. No new daemons, no app changes.

## Non-Goals (YAGNI)
- No launchd watcher / auto-import (add only if the manual step annoys).
- No reading the live Freeform board or writing into Freeform (impossible by design).
- No routing diagrams through the Obsidian vault (guarded prod surface).
- No OCR pipeline (Claude reads images directly).

## User-Facing?
**Yes** — this is a new way the user interacts with Selene's design process. On
wrap-up, add a guide at `docs/guides/features/diagram-loop.md` and link it from
`docs/USER-EXPERIENCE.md`.
