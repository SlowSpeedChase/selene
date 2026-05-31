# System Map

**What this does for you:** gives you one always-correct page that shows every workflow Selene runs — what it does, when it runs, and what it reads and writes — so you can understand the whole system at a glance without reading code, and trust that it's never silently out of date.

## Using it

Open **[`docs/SYSTEM-MAP.md`](../../SYSTEM-MAP.md)**. The top is a hand-written overview of how Selene flows (capture → process → deliver). Below it, under "Workflows (generated)", is a table with one row per workflow:

| Column | Meaning |
|--------|---------|
| Workflow | name, linked to its source file |
| Schedule | how often it runs (e.g. `every 5 min`, `hourly`, `daily 06:00`, or a webhook/route for on-demand ones) |
| Reads | the main tables/sources it reads from |
| Writes | the main tables/targets it writes to |
| Purpose | one plain-language line |

This is the **middle zoom level**. The ladder is: **[CLAUDE.md](../../../CLAUDE.md)** (what Selene is, where to go) → **this map** (the live inventory) → **[block diagrams](../../backend-block-diagrams.md)** + the workflow source files (the deep detail). Click a workflow name to drop straight into its code.

## How it works

The workflow table is **generated**, not hand-written. The generator `scripts/gen-system-map.ts`:

1. Reads every `src/workflows/*.ts` file (skipping `*.test.ts`).
2. Harvests a `// @map` comment block from the top of each file for its purpose, reads, and writes.
3. Looks up the schedule from the matching `launchd/com.selene.<name>.plist` (parsing `StartInterval`/`StartCalendarInterval`). Workflows with no plist fall back to a `// @map trigger:` line.
4. Writes the resulting table into `docs/SYSTEM-MAP.md` **between `<!-- GENERATED:workflows START -->` and `<!-- GENERATED:workflows END -->` markers**. Everything outside those markers (the hand-written overview) is never touched.

Because the facts come from the code itself, the table can't drift the way a hand-copied list does. The parsing/rendering logic lives in `src/lib/system-map.ts` (unit-tested in `src/lib/system-map.test.ts`).

**Drift guard:** the session-end hook (`.claude/hooks/session-end-reminders.sh`) runs `gen-system-map.ts --check` whenever a workflow or plist changed during a session. If the committed map no longer matches the code, it warns "docs/SYSTEM-MAP.md is OUT OF DATE" so the map gets regenerated before the change ships.

## Configure & customize

**Document a workflow** — add a `// @map` block at the very top of its file in `src/workflows/`:

```ts
// @map purpose: Extract concepts, themes, energy from pending notes
// @map reads: raw_notes
// @map writes: processed_notes
// @map trigger: webhook (POST /webhook/api/drafts)   // only for workflows with no launchd plist
```

- `purpose` is one line; `reads`/`writes` are comma-separated table or target names taken from the actual SQL.
- Omit `trigger` for scheduled workflows — the schedule comes from the plist automatically.
- A workflow with no `// @map` block still appears in the table (with `—` placeholders), so a new workflow can never be silently missing.

**Regenerate the map:**

```bash
npx ts-node scripts/gen-system-map.ts          # rewrite the table
npx ts-node scripts/gen-system-map.ts --check  # report drift without writing (exit 1 if stale)
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Hook says "SYSTEM-MAP.md is OUT OF DATE" | Run `npx ts-node scripts/gen-system-map.ts` and commit the updated `docs/SYSTEM-MAP.md` |
| A workflow's Purpose/Reads/Writes shows `—` | Add (or complete) its `// @map` block at the top of the workflow file, then regenerate |
| A workflow's Schedule shows `—` | It has no `launchd/com.selene.<name>.plist` — add a `// @map trigger:` line describing how it runs |
| Generator throws "missing the GENERATED:workflows markers" | The marker comments were deleted from `docs/SYSTEM-MAP.md` — restore both `<!-- GENERATED:workflows START -->` and `<!-- GENERATED:workflows END -->` lines |

## Related

- Design doc: `docs/plans/2026-05-31-living-system-map-design.md`
- Implementation plan: `docs/plans/2026-05-31-living-system-map-plan.md`
- Deep view: [Backend block diagrams](../../backend-block-diagrams.md)

---
*Last updated: 2026-05-31*
