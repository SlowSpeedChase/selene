# Obsidian Library

**What this does for you:** Selene automatically turns your captured notes into a browsable, organized Obsidian vault — every note as its own page, grouped into eight life-area maps, with a dashboard that shows what you've been thinking about lately.

## Using it

Selene builds and maintains an Obsidian vault for you. You don't trigger anything — new notes flow in on their own. You just open the vault and browse.

### Where the vault is

By default it lives at `vault/` inside the Selene project folder (`/Users/chaseeasterling/selene/vault`). Open that folder as a vault in Obsidian.

Everything Selene generates is under the **`Selene/`** folder inside the vault:

- **`Selene/Dashboard.md`** — your home base. Start here.
- **`Selene/Notes/`** — one page per captured note.
- **`Selene/Maps/`** — eight "Maps of Content" (MOCs), one per life area.

### The Dashboard

`Selene/Dashboard.md` is a scannable navigation hub (no walls of text). It has three sections:

- **Your Maps of Content** — a table of all eight categories with how many notes each holds and when each was last active. Click a category name to jump to its map.
- **Recently Captured** — your 10 newest notes, each with a one-line essence (or its title if no essence exists yet) so you can see at a glance what it was about.
- **Quiet Areas** — a gentle nudge listing categories that have had no new notes in the last 30 days, in case one is worth revisiting.

### The Maps (MOCs)

Each map in `Selene/Maps/` collects the notes for one life area and groups them under named sub-sections that Selene writes for you. The eight maps are:

- Personal Growth
- Relationships & Social
- Health & Body
- Projects & Tech
- Career & Work
- Creativity & Expression
- Politics & Society
- Daily Systems

Every note lives in one primary map but can also show up as a cross-reference ("See Also") in 1–2 related maps, so a note about a side project's effect on your health is findable from both places.

### The Notes

Each page in `Selene/Notes/` is one captured note: its original text, the date, its theme and concepts (as Obsidian `[[wiki-links]]` you can click to explore), and a short italic essence summary when one exists.

## How it works

- **Workflow:** `src/workflows/export-obsidian.ts`
- **Wrapper script:** `scripts/selene-export-obsidian` (runs `npx ts-node src/workflows/export-obsidian.ts`)
- **launchd agent:** `com.selene.export-obsidian` (`launchd/com.selene.export-obsidian.plist`)
- **Schedule:** every hour, at the top of the hour (`StartCalendarInterval` → `Minute 0`)
- **Logs:** `logs/export-obsidian.log` and `logs/export-obsidian.error.log`

Each run happens in two phases:

**Phase 1 — Export notes (always runs, idempotent).** Looks at **every** processed note (test notes excluded), renders each one's full markdown, and compares a hash of that rendered page to the hash stored from the last export. A note is rewritten **only when its rendered output changed** — a new cluster link, an updated essence, a theme change — and skipped cheaply when nothing changed. This makes the vault **self-healing**: improvements Selene makes to a note *after* its first export now reach the page, instead of being frozen at whatever the very first export produced. Files are written to `Selene/Notes/` as `YYYY-MM-DD-slug.md`. To avoid one giant pass, each run writes at most ~200 changed files; if more changed, the rest drain on the next hourly run (the log reports a `deferred` count when that happens).

> **These pages are generated artifacts — don't hand-edit them.** Because Selene rewrites a note's page whenever its content changes, any manual edits to files in `Selene/Notes/` will be overwritten on a later export. Treat them as read-only output; capture changes as new notes instead.

**Phase 2 — Generate maps and dashboard.**

- **Maps (MOCs):** regenerated **only when at least one note was (re)written in Phase 1 _and_ Ollama is available.** A local LLM groups each category's notes into named sub-sections. Each map is written to `Selene/Maps/<Category>.md`. If nothing changed, the maps are left as-is (no needless rebuilds).
- **Dashboard:** regenerated on **every** run and is **code-generated, not LLM-generated** — so its links always point to real pages (no hallucinated or empty stub links). Written to `Selene/Dashboard.md`.

## Configure & customize

### Vault location

The output vault path is resolved in `src/lib/config.ts` (`getVaultPath()`). In production (the default) it is `vault/` inside the project root. You can override it without touching code:

- Set **`SELENE_VAULT_PATH`** in your `.env` to point anywhere, e.g. `SELENE_VAULT_PATH=/Users/chaseeasterling/Documents/MyVault`.
- The workflow also honors **`OBSIDIAN_VAULT_PATH`**, which takes precedence if set (see `export-obsidian.ts`, where it falls back to the config value when unset).

### Schedule

To change how often the vault rebuilds, edit `launchd/com.selene.export-obsidian.plist` (the `StartCalendarInterval` block), then reload it:

```
launchctl bootout gui/$(id -u)/com.selene.export-obsidian 2>/dev/null
launchctl bootstrap gui/$(id -u) launchd/com.selene.export-obsidian.plist
```

### Run it by hand

To rebuild the vault immediately (useful after capturing a batch of notes):

```
npx ts-node src/workflows/export-obsidian.ts
```

The categories themselves are fixed in code (`CATEGORIES` in `src/lib/prompts.ts`) and are not meant to be changed casually — they're the same eight categories the note-processing step assigns to.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Vault folder is empty or missing | Confirm where it's pointing: in production it's `vault/` in the project root unless `SELENE_VAULT_PATH` / `OBSIDIAN_VAULT_PATH` is set. Force a run: `npx ts-node src/workflows/export-obsidian.ts` |
| New notes aren't showing up in the vault | Notes only export once they're fully **processed**. Check the log: `tail -f logs/export-obsidian.log`. Then force a run: `npx ts-node src/workflows/export-obsidian.ts` |
| Maps (MOCs) look stale / didn't update | Maps only regenerate when new notes were exported **and** Ollama is running. Confirm Ollama is up (`curl http://localhost:11434/api/tags`), then force a run: `npx ts-node src/workflows/export-obsidian.ts` |
| Dashboard didn't update | The dashboard regenerates on every run. Check for errors: `tail -f logs/export-obsidian.error.log`. Force a run: `npx ts-node src/workflows/export-obsidian.ts` |
| Want to force the scheduled job now | `launchctl kickstart -k gui/$(id -u)/com.selene.export-obsidian` |
| A note shows under the wrong map | The category is assigned during note processing, not by this export. Uncategorized notes fall back to **Daily Systems**. Re-processing the note (upstream) is what changes its category. |
| My hand-edits to a note page disappeared | Expected — `Selene/Notes/` pages are regenerated whenever the note's content changes. Don't edit them directly; they're output, not source. |
| Notes are missing constellation (`parent::`) links | Run the export; it now backfills links for the whole corpus, not just newly captured notes. After a large backfill, check the log for a `deferred` count — if non-zero, a second run finishes the rest. |

## Related

- Design docs in `docs/plans/`:
  - `docs/plans/2026-03-21-obsidian-librarian-design.md` (the curated vault: notes, topic indexes, dashboard)
  - `docs/plans/2026-03-21-obsidian-moc-design.md` (the eight fixed categories, Maps of Content, and code-generated dashboard)
  - `docs/plans/2026-05-30-idempotent-obsidian-reexport-design.md` (the content-hash re-export that makes the vault self-healing)
- Connected guides:
  - [Capturing notes](capturing-notes.md) (how notes get into Selene in the first place)
  - [Daily digest](daily-digest.md) (the daily summary, which also lands in the vault)
  - [Knowledge constellation](knowledge-constellation.md) (the `parent::` links this export now backfills across the whole corpus)

---
*Last updated: 2026-05-30*
