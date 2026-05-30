# PKM Browse (iPad dashboard)

**What this does for you:** a read-only web dashboard for your notes you open on the iPad over your home WiFi — browse by category or concept, skim essences, see "on this day," and get a small set of notes resurfaced for review. One URL, no app, no login.

## Using it

1. On the iPad (same WiFi as your Mac), open `http://<mac-lan-ip>:5678/pkm/` in Safari and bookmark it.
2. The **home** page shows: recent essences, your top concepts, the category grid, a note to revisit, "on this day," and how many notes are due for review.
3. Tap into:
   - **Categories** → a category → its notes (including notes that only *cross-reference* the category).
   - **Concepts** → a concept → notes with that concept + the concepts it most often appears alongside.
   - **A note** → its essence, content, concepts, and category. Opening a note marks it "surfaced" so it rotates out of the review queue.
   - **Review today** → notes you haven't seen in 7+ days (least-seen first) + one random essence.
   - **On this day** → notes from this calendar day in earlier years.

## How it works

The existing Fastify server (`com.selene.server`, port 5678) serves these pages under `/pkm/*` — no extra process. The code is three small modules:

- `src/lib/pkm-queries.ts` — all read-only SQL. Every query gates on `test_run IS NULL AND status='processed'` (centralized in `baseNoteFilter()`), so test notes never show. Concept/cross-ref membership uses `json_each` (guarded by `json_valid`).
- `src/lib/pkm-render.ts` — plain HTML pages (no client JavaScript), one dark-mode-aware layout, all user text HTML-escaped.
- `src/routes/pkm.ts` — the route handlers + the LAN guard.
- `src/lib/pkm-db.ts` — the `pkm_review_state` table that powers spaced resurfacing.

Spaced resurfacing: viewing a note calls `markSurfaced('note', id)`; the review queue (`getDueForReview`) returns notes never surfaced or unseen for `REVIEW_WINDOW_DAYS` (7), least-surfaced and oldest first.

## Configure & customize

- **Review window:** `REVIEW_WINDOW_DAYS` in `src/lib/pkm-db.ts` (default 7).
- **Essence page size:** `PAGE_SIZE` in `src/routes/pkm.ts` (default 50).
- **Allowed networks:** `isLanIp()` in `src/routes/pkm.ts` allows loopback + `10/8`, `192.168/16`, `172.16–31`, and your **Tailscale** tailnet (`100.64.0.0/10`) — so you can browse over Tailscale when away from home, not just on local WiFi.
- **Categories** come from the synthesis pipeline (the 8 controlled categories); concepts/essences from `process-llm`/`distill-essences`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `403 PKM browse is LAN-only` | You're hitting it from an IP outside loopback/RFC1918/Tailscale. Use the Mac's local WiFi address (same network) or its Tailscale address over Tailscale; don't port-forward 5678 to the public internet. |
| A category/concept page is empty | Those notes may be unclassified or pre-date categorization — run the category backfill / let the pipeline catch up. |
| A page errors on one note | Concept JSON is guarded (`json_valid`), so a bad row degrades to empty rather than crashing — check that note's `processed_notes.concepts`. |
| Page not found at `/pkm/` | Confirm the server is running (`curl -s localhost:5678/health`) and on a build that includes the PKM routes. |

## Related

- Design doc: `docs/plans/2026-04-12-pkm-browse-layer-design.md`
- Operator notes: `.claude/OPERATIONS.md` → "Browse on iPad (PKM dashboard)"
- Connected guides: `docs/guides/features/obsidian-library.md` (the offline vault view), `docs/guides/features/synthesis-layer.md`
- **Not yet built:** Track 3 (Obsidian exporter slim upgrade) — keeps the vault useful as the offline view.

---
*Last updated: 2026-05-30*
