# Synthesis Layer

**What this does for you:** Selene groups everything you capture by **what it's about** (not where it came from), tells you what topics you keep circling, when your understanding of something shifted, and what last night's notes unexpectedly connect to from months ago — without you tagging, searching, or remembering anything. The same groups are what the **iPad Notes browse** shows.

## Using it

There's nothing to do. The synthesis layer runs automatically and:

1. **Groups your notes into content categories.** Every note is sorted into one or more of 8 fixed categories by what it's about. A multi-topic brain-dump page appears under **every** category it touches — so a page about your health, a project, and a relationship shows up in all three. This is what the iPad Notes section lists (largest category first).
2. **Adds synthesis sections to your 6am Apple Notes digest:**

```
## Topics circling
Relationships & Social (120 notes) — You've been exploring how to
show up for the people around you while protecting your own energy,
with a recurring thread about boundaries and follow-through.
The open question: ...

## Understanding shifted
Personal Growth: The angle shifted toward identity, not just habit.

## Unexpected connections
"Friction in the morning" → "The cost of starting" (Feb 2026, 88% match)
```

On Sundays, a **weekly evolution rollup** summarises how your understanding across all topics shifted during the week.

## How it works

**The 8 categories** are a fixed list in `src/lib/prompts.ts` (`CATEGORIES`): Personal Growth, Relationships & Social, Health & Body, Projects & Tech, Career & Work, Creativity & Expression, Politics & Society, Daily Systems. `process-llm.ts` assigns each note a primary `category` and optional `cross_ref_categories` when it first processes the note.

**Three signals, two workflows:**

| Signal | When | Workflow |
|--------|------|----------|
| **Category grouping + synthesis** | At `synthesize-topics` run | `src/workflows/synthesize-topics.ts` |
| **Evolution detection** | At `synthesize-topics` run | `src/workflows/synthesize-topics.ts` |
| **Connection detection** | Every 5 min (at process time) | `src/workflows/process-llm.ts` |

**synthesize-topics.ts** (category-derived clustering):
1. Loads every processed note with its `category` + `cross_ref_categories`.
2. Builds **one `topic_clusters` row per non-empty category**, named from the fixed list — so a cluster can never be named after a *source* (the old embedding clusterer once produced a 104-note "E-Ink Empowerment" bucket; that can't happen now).
3. Links each note to **every** category it belongs to (`topic_note_links`, many-to-many) → genuine multi-topic membership. `note_count` is the distinct number of member notes.
4. Generates an Ollama synthesis narrative (mistral:7b) per category, weaving in that category's recurring concepts. The narrative regenerates only when a category's membership changed since the last run (a delta-guard skips unchanged categories).
5. Runs an evolution check when a category's synthesis changed; on Sundays, a weekly rollup summarises the week's evolution events.
6. Removes any stale clusters: empty categories and leftover clusters from the old embedding scheme are deleted automatically every run.

**process-llm.ts (connection detection):** After extracting a note's concepts, it generates an embedding and searches LanceDB for older notes (>7 days) with ≥ 75% similarity; surprising matches go to `note_connections`. *(Embeddings still power connection-finding and search — only cluster membership moved off embeddings.)*

**send-digest.ts:** Reads these tables and appends the synthesis sections to the digest before posting to Apple Notes.

**Tables:** `topic_clusters`, `topic_note_links`, `note_connections`, `synthesis_meta` (no schema change for this feature — the rewrite changed only what populates `topic_clusters`/`topic_note_links`).

**Launchd agent:** `com.selene.synthesize-topics` (prod: `com.selene.prod.synthesize-topics`).

## Configure & customize

| Setting | Where | Default |
|---------|-------|---------|
| The category list | `src/lib/prompts.ts` `CATEGORIES` | 8 categories |
| Synthesis context window | `src/workflows/synthesize-topics.ts` (`numCtx` on the synthesis call) | `4096` |
| Members fed to one synthesis prompt | `src/workflows/synthesize-topics.ts` (`members.slice(0, 40)`) | `40` |
| Connection similarity threshold | `src/workflows/process-llm.ts` `CONNECTION_THRESHOLD` | `0.75` |

**Notes:**
- Cluster membership is **deterministic** — it follows each note's category, so there is no similarity threshold to tune anymore.
- To force a full rebuild (e.g. after changing the category list or migrating off the old embedding clusters), run with `SELENE_REBUILD_CLUSTERS=1`, which wipes `topic_clusters`/`topic_note_links` first. Normal runs reconcile in place.
- A note's category quality depends on `process-llm.ts`'s classification. To reclassify older notes that predate the category feature, run `scripts/backfill-categories.ts` (it also resets `exported_to_obsidian` so the Obsidian Maps of Content rebuild).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| iPad Notes browse empty / no "Topics circling" | Run `npx ts-node src/workflows/synthesize-topics.ts`; check `sqlite3 data/selene.db "SELECT name, note_count FROM topic_clusters WHERE is_proto=0 ORDER BY note_count DESC;"` |
| A category is missing from the browse | It has zero member notes. Check `sqlite3 data/selene.db "SELECT category, COUNT(*) FROM processed_notes GROUP BY category;"` — if many notes have `NULL` category, run `scripts/backfill-categories.ts` |
| A note isn't in any category | Its `category` is `NULL` (classification failed). Re-run `scripts/backfill-categories.ts`; the workflow logs the IDs of un-categorized notes ("no silent drops") |
| Old source-named cluster still showing (e.g. "E-Ink Empowerment") | Run once with `SELENE_REBUILD_CLUSTERS=1` to wipe legacy clusters; the always-on orphan cleanup removes them on subsequent runs too |
| Synthesis seems to ignore some notes in a big category | Expected: only the first 40 members feed one synthesis prompt (logged when capped). Raise the cap if needed |
| `note_connections` always empty | Normal until notes have been processed for 7+ days |
| launchd agent not in list | Run `./scripts/install-launchd.sh` and check `launchctl list \| grep synthesize` |

## Related

- Design doc: `docs/plans/2026-05-29-content-based-multitopic-clustering-design.md`
- Implementation plan: `docs/plans/2026-05-29-content-based-multitopic-clustering.md`
- Original synthesis design: `docs/plans/2026-05-26-synthesis-retrieval-agent-design.md`
- Connected guides: `docs/guides/features/daily-digest.md`, `docs/guides/features/note-annotation.md` (the iPad Notes browse), `docs/guides/features/obsidian-library.md`

---
*Last updated: 2026-05-29*
