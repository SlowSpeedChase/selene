# Recipe → KitchenOS

**What this does for you:** paste an AI-written recipe into Drafts, tap one action, and it lands in your KitchenOS recipe vault — no SSH, from any machine.

## Using it

1. Create a recipe however you like (e.g. chatting with Claude on another machine).
2. Copy the recipe text into a Drafts note.
3. Run the **Send Recipe to KitchenOS** action.

The action posts to Selene, which stores the note like any capture and returns immediately. KitchenOS parses the text in the background (a local LLM, ~1–2 min) and writes the recipe to the Obsidian vault. You don't wait on the parse.

If a parse comes out wrong, the original text is preserved inside the recipe file (a collapsible **Import Source** block), and re-sending a corrected paste overwrites the recipe (KitchenOS backs up the previous version first).

### Drafts action setup

HTTP POST action:
- URL: `http://chases-mac-mini.taila69703.ts.net:5678/webhook/api/recipe` (Tailscale hostname so other machines reach the Mac mini)
- Body (JSON): `{"title": "[[title]]", "content": "[[draft]]"}`

## How it works

- Route: `src/routes/recipe.ts` → `POST /webhook/api/recipe` (no auth, matching `/webhook/api/drafts`).
- It calls the existing `ingest()` workflow to store the note in Selene (dedup by content hash), responds immediately, then fire-and-forgets a `fetch()` to KitchenOS `POST /api/recipes/import-text`.
- KitchenOS parses the raw text with Ollama and saves the formatted recipe to the vault.
- Captures carrying a `test_run` marker are stored in Selene only and are **not** forwarded to the recipe vault.

If KitchenOS is down, the note is still safe in Selene; the failed forward is logged (`module: recipe-route`) for a manual retry.

## Configure & customize

| Knob | Where | Default |
|------|-------|---------|
| KitchenOS API base URL | `KITCHENOS_API_URL` env var (`src/lib/config.ts` → `kitchenosApiUrl`) | `http://localhost:5001` |

Both servers run on the Mac mini, so the default localhost URL is correct in production; override only if KitchenOS moves.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Recipe never appears in the vault | Check `tail -f logs/selene.log` for `module: recipe-route`; a "KitchenOS import failed" line means the KitchenOS API was unreachable — verify `curl http://localhost:5001/health`. |
| Parse looks wrong | Open the recipe in Obsidian, fix it by hand, or re-send a corrected paste through the same Drafts action (it overwrites, with a backup). |
| Drafts action hangs | It shouldn't — Selene replies before the parse. A hang means Selene itself is down: `curl http://localhost:5678/health`. |

## Related

- KitchenOS endpoint: `api_server.py` → `/api/recipes/import-text`
- Connected guides: [Capturing notes](capturing-notes.md)

---
*Last updated: 2026-06-16*
