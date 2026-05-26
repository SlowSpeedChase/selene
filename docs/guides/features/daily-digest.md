# Daily Digest

**What this does for you:** Every morning at 6am, a short summary of your recent notes — themes and patterns Selene noticed — appears in an Apple Note so you can skim it without searching.

## Using it

This is your entire morning Selene interaction (about 5 minutes):

1. Open **Apple Notes** on your phone or Mac around 6am.
2. Find the note titled **Selene Daily**. If you pin it once (see [Configure & customize](#configure--customize)), it stays at the top of your notes list every day.
3. Skim it. The note is overwritten with fresh content each morning — there's just one "Selene Daily" note, not a new one per day.

You're looking for surprises: things you captured but already forgot, recurring themes across the past week, and ideas that connected. The digest is a handful of short lines — it's meant to be glanced at, not studied.

> If the note isn't there, see [Troubleshooting](#troubleshooting).

## How it works

You experience this as one "morning digest," but behind the scenes it's two background workflows that run at different times. Both are scheduled by launchd and run automatically — you don't touch them.

**1. Overnight: the summary is generated (midnight)**

- Workflow: `src/workflows/daily-summary.ts`
- launchd agent: `launchd/com.selene.daily-summary.plist` — runs at **00:00 (midnight)**
- What it does: pulls your notes from the **past 7 days** (skipping test data), asks the local LLM to write a short summary of the main lines of thought, patterns, and what might need attention. It then condenses that into 3–5 short bullet lines and saves them as a digest text file. It also writes a fuller daily-summary markdown file into your Obsidian vault under `Selene/Daily/`.
- If no notes were captured in the window, it skips quietly. If the local LLM (Ollama) is offline, it writes a plain fallback summary instead.

**2. Morning: the digest is delivered to Apple Notes (6am)**

- Workflow: `src/workflows/send-digest.ts`
- launchd agent: `launchd/com.selene.send-digest.plist` — runs at **06:00 (6am)**
- What it does: reads the digest text file created overnight (today's, falling back to yesterday's), formats it as simple HTML, and writes it into an Apple Note named **Selene Daily** via AppleScript. If a note with that name already exists, its body is overwritten; otherwise a new one is created.

So the chain is: **midnight → summary written → 6am → delivered to the "Selene Daily" Apple Note.**

## Configure & customize

**The Apple Note title**
The note is named **`Selene Daily`**. This is set in `src/workflows/send-digest.ts`:

```ts
const DIGEST_NOTE_NAME = 'Selene Daily';
```

To rename it, change that string and re-run the workflow.

**Pin the note (one-time)**
The workflow does not pin the note for you. After it appears the first time, right-click (or swipe) the **Selene Daily** note in Apple Notes and choose **Pin**. Pinned status persists even when the body is overwritten each morning, so you only do this once.

**The schedules**
Edit the `StartCalendarInterval` block (`Hour` / `Minute`) in the plist, then reinstall the agents:

- Summary time: `launchd/com.selene.daily-summary.plist` (currently `Hour 0`, `Minute 0`)
- Delivery time: `launchd/com.selene.send-digest.plist` (currently `Hour 6`, `Minute 0`)

```bash
./scripts/install-launchd.sh
```

**Turn the Apple Notes digest off**
Delivery to Apple Notes is controlled by an environment variable. It is **on by default** in production and turns off only if you explicitly set:

```bash
APPLE_NOTES_DIGEST_ENABLED=false
```

(In test and development environments it is disabled automatically.)

**Obsidian vault location for the fuller summary**
The overnight markdown summary is written under the Obsidian vault. Override the vault path with:

```bash
OBSIDIAN_VAULT_PATH=/path/to/your/vault
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| No "Selene Daily" note this morning | Regenerate and deliver it now: `npx ts-node src/workflows/send-digest.ts` |
| Note exists but content looks empty or stale | The overnight summary may not have run. Regenerate it, then deliver: `npx ts-node src/workflows/daily-summary.ts` then `npx ts-node src/workflows/send-digest.ts` |
| Want to confirm the 6am delivery actually ran | `launchctl list \| grep selene` — find the `com.selene.send-digest` row; the second number is the exit status, where `0` means it ran cleanly and `-` means it hasn't run yet |
| Summary says "Ollama was offline" or has no AI text | The local LLM wasn't running. Start it (`ollama serve`), then regenerate: `npx ts-node src/workflows/daily-summary.ts` |
| "No notes this week" / digest skipped | Expected if nothing was captured in the past 7 days — capture some notes and it will populate next run |
| Need to see what went wrong | `tail -f logs/selene.log \| npx pino-pretty` (or `logs/send-digest.error.log` / `logs/daily-summary.error.log`) |
| Restart all background agents | `./scripts/install-launchd.sh` |

## Related

- Design doc: `docs/plans/2026-02-12-apple-notes-daily-digest-design.md`
- Connected guides:
  - [Capturing notes](capturing-notes.md) — how notes get into Selene in the first place
  - [Obsidian library](obsidian-library.md) — where the fuller daily summary and your full note archive live

---
*Last updated: 2026-05-25*
