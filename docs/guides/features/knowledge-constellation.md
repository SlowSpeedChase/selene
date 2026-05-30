# Knowledge Constellation

**What this does for you:** turns your notes into a navigable visual map in Obsidian — a "fly-through" graph where each note sits under its topic cluster(s), so you can see the shape of your thinking and click from note to cluster to note instead of holding it in your head.

## Using it

1. In your Selene Obsidian vault, install three community plugins: **Dataview**, **Excalidraw**, and **ExcaliBrain** (ExcaliBrain depends on the other two).
2. Open any note under `Notes/` and launch **ExcaliBrain** (command palette → "ExcaliBrain: Open").
3. The note shows its **topic cluster as a parent** above it; centering the cluster shows all its member notes as **children**. A note that belongs to several clusters appears under each — click any node to recenter and keep flying through.
4. The cluster nodes themselves are the `Constellation/` index notes (one per cluster).

This is read-only navigation — you don't maintain the map by hand. Selene regenerates it on every export.

## How it works

The hourly export workflow (`src/workflows/export-obsidian.ts`, run by the `com.selene.prod.export-obsidian` launchd agent) does two constellation things, both driven entirely by the synthesis tables — no new computation:

- **`parent::` fields on notes** — for each exported note, it looks up the note's cluster(s) in `topic_note_links` ⋈ `topic_clusters` and writes one `parent:: [[<cluster>]]` Dataview line per cluster (multi-membership safe). `parent::` is ExcaliBrain's default parent field, so no plugin config is needed.
- **`Constellation/` index notes** — one markdown file per cluster (`Constellation/<cluster>.md`), regenerated wholesale each run (idempotent — re-running overwrites identically, no duplicates).

The clusters come from the nightly `synthesize-topics` agent (2am), which builds one cluster per content category from each note's `category`/`cross_ref_categories`. So the constellation reflects the same 8 content categories you see in the Notes browse.

The pure logic lives in `src/lib/constellation.ts` (unit-tested in `constellation.test.ts` / `constellation.db.test.ts`); `export-obsidian.ts` just calls it.

## Configure & customize

- **Vault location:** `SELENE_VAULT_PATH` (prod = the iCloud Obsidian vault). The `Notes/` and `Constellation/` directories live there.
- **Cluster set:** determined upstream by `synthesize-topics.ts` (the 8 controlled categories). To change what clusters exist, change categorization, not the constellation code.
- **Filenames:** cluster index notes use a wikilink-safe basename (`clusterNoteFilename` strips `[ ] / \ : # ^ |`; keeps `&` and spaces). `parent::` links reference that exact basename so ExcaliBrain resolves them.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Clusters don't render in ExcaliBrain | Confirm **Dataview** is enabled, and that a note's `parent:: [[X]]` basename exactly matches a file in `Constellation/` (the #1 failure mode). |
| A note has no parent cluster | It isn't in any `topic_note_links` row yet — it may be unclassified. Re-run `synthesize-topics` so it joins a category cluster. |
| Only recent notes connect to clusters; older notes float free | Run the export — it now re-checks **every** note each run and backfills `parent::` links across the whole corpus, not just newly captured notes. A large first backfill may take two hourly runs to fully drain (the log shows a `deferred` count when it does). |
| Graph looks stale after notes changed | Re-run the export: `npx ts-node src/workflows/export-obsidian.ts` (or wait for the hourly agent). Output fully regenerates. |
| Duplicate / broken nodes after a re-run | Shouldn't happen — `Constellation/` and `parent::` are deterministic. If it does, delete `Constellation/` and re-export. |

## Related

- Design doc: `docs/plans/2026-05-29-knowledge-constellation-design.md`
- Phase A plan: `docs/plans/2026-05-29-knowledge-constellation-phase-a-plan.md`
- Research: `docs/plans/2026-05-29-excalidraw-excalibrain-research.md`
- Connected guides: `docs/guides/features/synthesis-layer.md` (where the clusters come from)
- **Phase B (not yet built):** note↔note `friend::` edges, gated on the empty `note_connections` table.

---
*Last updated: 2026-05-30*
