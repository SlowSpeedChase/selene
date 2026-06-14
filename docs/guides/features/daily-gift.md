# Daily Gift

**What this does for you:** Every time you open the daily worksheet, Selene shows you ≤3 notes it quietly noticed — an old thought you buried, two ideas that turn out to be connected, a recent note heating up — and gives you four guilt-free taps to react.

## Using it

Open **SeleneMarkup** on your iPad and go to the **Worksheet** tab. The gift section appears at the top, above the handwriting fields.

Each card shows:
- A small muted label for what kind of surfacing this is (see the three slot types below)
- The note title and a snippet
- Four tap buttons: **Important · Keep · Not now · Let go**

You don't have to react to anything. Tap what feels true; tap again to un-select. Then submit the worksheet as usual — reactions go along for the ride, bundled with your handwritten answers.

**The three slot types:**

| Label | What it surfaces |
|-------|-----------------|
| **buried treasure** | A random note older than 2 weeks you've never reacted to |
| **connecting thought** | A recent note (≤7 days old) linked to an older one (≥14 days) by semantic similarity — two ideas that share a thread |
| **recently heating up** | The most recently captured note you haven't reacted to yet |

Notes you've already reacted to are automatically excluded from future slots.

**Cold start:** If you have no reaction history yet, buried treasure picks a random old note and heating up picks your newest note. The connection slot may be absent if note_connections are sparse.

## How it works

**Slot selection** happens at worksheet-generation time in `src/routes/worksheets.ts → fetchGiftItems()`. Three SQLite queries run against `selene.db` (cross-referencing `facts.attention_log` via ATTACH). The gift section is always the **first field** in the worksheet's `fields` array, so it renders above the pencil fields on the iPad.

**Reaction storage** — when you submit, each reacted card writes one row to `facts.attention_log` in `facts.db` (precious — survives a `rebuild`). Skipped cards write nothing; a non-reaction is not a reaction. The table:

```sql
attention_log (id, worksheet_id, note_id, slot_role, reaction, reacted_at)
```

**Salience score** — not stored, computed on demand when the log has enough data:

```
score = engagement_count / (hours_since_last_reaction + 2) ^ 1.5
```

`engagement_count` = number of `important`/`keep`/`not_now` taps (not `let_go`). Once data accumulates, slot queries can rank candidates by salience instead of recency/random — the slot logic doesn't change, just the ordering.

**iPad rendering** — `GiftSurfaceView.swift` in SeleneMarkup renders above the pencil fields via the `gift_surface` field kind. The field switch in `WorksheetView` gained a `.gift_surface` case; submit collects `noteId + reaction + slotRole` per tapped card.

## Configure & customize

| What | Where |
|------|-------|
| Number of buried_treasure / heating_up notes to surface | `src/routes/worksheets.ts` — `LIMIT 1` in each slot query |
| Minimum age for buried_treasure | Same file — `datetime('now', '-14 days')` |
| Minimum age for connection slot "old" side | Same file — `datetime('now', '-14 days')` in the connection query |
| `attention_log` table definition | `src/lib/facts-db.ts → initFactsSchema()` |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Gift section doesn't appear on worksheet | The slot queries returned 0 items (new install with no notes older than 14 days, or all notes already reacted to). Submit the worksheet anyway; it'll appear once the archive ages. |
| Worksheet loads but shows an error | Server returned a non-200. Check: `tail -f logs/selene.log \| npx pino-pretty` |
| Reactions not in `attention_log` | Confirm you tapped Submit (not just navigated away). Check: `sqlite3 ~/selene-data/facts.db "SELECT * FROM attention_log ORDER BY id DESC LIMIT 5;"` |
| Connection slot never appears | `note_connections` may be empty or all edges are within the same age window. Check: `sqlite3 ~/selene-data/selene.db "SELECT COUNT(*) FROM note_connections;"` — if 0, the backfill hasn't run yet. |
| App can't reach server | Confirm Mac and iPad are on the same WiFi. Check `AppConfig.swift → baseURL`. |

## Related

- Design doc: `docs/plans/2026-06-13-act0-daily-gift-design.md`
- Plan doc: `docs/plans/2026-06-13-act0-daily-gift-plan.md`
- Parent vision: `docs/plans/2026-06-07-executive-assistant-wants-design.md`
- iPad app: `~/SeleneMarkup/Sources/SeleneMarkup/Views/GiftSurfaceView.swift`
- Slot queries: `src/routes/worksheets.ts → fetchGiftItems()`
- Worksheet guide (full worksheet context): `docs/guides/features/interactive-worksheets.md`

---
*Last updated: 2026-06-14*
