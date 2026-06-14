# Selene Diagrams

Hand-drawn diagrams of how Selene works / should work, captured in the
**Freeform ⇄ repo visual thinking loop** (see
[design doc](../plans/2026-06-08-freeform-diagram-loop-design.md) ·
[plan](../plans/2026-06-08-freeform-diagram-loop-plan.md)).

Each keeper is a pair: `<topic>.png` (the drawing) + `<topic>.md`
(Claude's reading of it + links to any design docs it spawned).

**Overwrite, never accumulate:** re-drawing a topic overwrites the same
`<topic>.png`/`<topic>.md` in place — git history is the version store
(`git log -- docs/diagrams/<topic>.png` recovers any past version), and this
folder stays clean. Update a topic's row below rather than adding a duplicate.

## How a lap works

1. **Seed** — `npx ts-node scripts/render-seed-diagram.ts` renders the current
   system to `Selene-Diagrams/seed-*.png` in iCloud Drive.
2. **Draw** — on iPad, open Freeform → insert that seed image → draw → share-sheet
   → Save to Files → `Selene-Diagrams`.
3. **Capture** — tell Claude "new diagram"; Claude reads the newest export,
   writes the keeper pair here, and commits.

## Index

| Diagram | Captured | What it's about |
|---------|----------|-----------------|
| _(none yet — first lap pending)_ | | |
