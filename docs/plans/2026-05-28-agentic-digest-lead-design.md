# Agentic Digest — "Worth Your Attention" Lead Line

**Date:** 2026-05-28
**Status:** Ready
**Topic:** digest, daily-summary, ollama, adhd, attention
**Source:** Lesson #1 in `2026-05-28-competitive-landscape-research.md` (Saner.ai's morning proactive scan; Limitless daily briefing)

---

## Vision

The 6am "Selene Daily" note currently *reports* — yesterday's/this week's captures condensed
into 3–5 bullets. For ADHD, a wall of summary is still a wall: it tells you what happened but
not what to *do* with it. This change adds a single **lead line** at the top of the digest —
"Worth your attention today" — that names the one thing most worth re-engaging with, derived
from the notes the summary already covers. One sharp line above the summary, not a second
summary.

This is the smallest, highest-leverage change from the competitive scan: it turns a passive
report into an attention-director without new infrastructure, new surfaces, or new processes.

---

## Goals / Non-Goals

**Goals**
- Prepend exactly one focusing line to the digest text: the single most important active thread + an implied next move.
- Generate it from data `daily-summary.ts` already has in memory (no new query, no new table).
- One extra Ollama call. Degrade cleanly to *no lead line* (never a fabricated one) when Ollama is offline.
- Render correctly as the first paragraph in the Apple Note and in the TRMNL payload, unchanged renderers.

**Non-Goals**
- Spaced resurfacing of *forgotten* notes — that's lesson #2, a separate doc (it reaches backward into the archive; this line works from the week's active notes).
- Multiple suggestions, a ranked list, or a "top 3." Exactly one line — the ADHD point is singular focus.
- Any change to `send-digest.ts`'s posting logic or the `{date}-digest.txt` file contract beyond the first line.

---

## Architecture

No new files. The lead line is generated where the summary and note data already live:
`src/workflows/daily-summary.ts` (runs midnight via `com.selene.daily-summary`). `send-digest.ts`
(6am) is unchanged — it already renders each non-empty line of the digest file as a `<p>`
(`digestToHtml`) and as a TRMNL bullet (`buildTrmnlPayload`), so a new first line flows through
both surfaces automatically.

```
daily-summary.ts (midnight)
  1. query past-week notes            (existing)
  2. SUMMARY_PROMPT  → summary        (existing)
  3. LEAD_PROMPT     → lead line      ← NEW (one Ollama call, uses summary + note essences)
  4. DIGEST_PROMPT   → condensed body (existing)
  5. write `{date}-digest.txt` as:    ← lead line is line 1, blank line, then condensed body
        Worth your attention: <lead>
        <existing condensed digest>
        ↓
send-digest.ts (6am) — UNCHANGED — renders line 1 as the first <p> / first bullet
```

### LEAD_PROMPT (new constant in daily-summary.ts)

```
You are helping someone with ADHD decide where to put their attention today.

This week's summary:
{summary}

The most active notes:
{topNoteEssences}

In ONE sentence, name the single most important thread and the natural next move on it.
Be specific and concrete — reference the actual topic, not "your notes."
Start with a verb or the topic name. No preamble, no "you should consider."
If nothing clearly stands out, return the most recurring topic as a gentle observation.
Return only the sentence.
```

`{topNoteEssences}` = the same `notes` array already loaded, take the most recent ~8 essences
(fallback to concepts/title slice, mirroring the existing `notesText` builder). Temperature low
(0.3) for a crisp, grounded line.

### Assembly

- If `isAvailable()`: generate the lead, trim it, and prepend `"Worth your attention: " + lead + "\n\n"` to the condensed digest before `writeFileSync`.
- If Ollama is offline at lead-generation time: skip the prefix entirely. The digest is still written from its existing fallback. **Never** emit a placeholder lead.
- Guard against a model that returns multiple lines: take the first non-empty line only.

---

## Acceptance Criteria

- [ ] On a week with notes, `{date}-digest.txt` line 1 is a single sentence naming a specific topic + next move (not "you captured N notes").
- [ ] The lead line references real content from the week (manual read of one real run).
- [ ] When Ollama is offline, the digest is written with **no** lead line and no placeholder text (verified by stubbing `isAvailable()` → false in test env).
- [ ] `send-digest.ts` renders the lead as the first `<p>` in the Apple Note and the first TRMNL bullet — no change to `send-digest.ts` required.
- [ ] A model response with multiple lines is truncated to one line (unit test on the truncation helper).
- [ ] Test-env run writes to the `sent/` file with the lead line present (existing `sendDigestToFile` path); cleaned up after.
- [ ] No new SQL query, table, or launchd agent added.

---

## ADHD Check

- **Reduces friction:** removes the "read the whole digest and decide what matters" step — the deciding is done for you.
- **Externalizes cognition:** the system holds "what's most important right now" so you don't have to reconstruct it each morning.
- **Visible:** it's the first thing you see in the pinned note; no searching, no scrolling.
- **Realistic:** one line, one thread. Singular focus is the ADHD-correct dose; a ranked list would reintroduce the wall.
- **No guilt:** phrased as an offer/observation ("Worth your attention: …"), never "you failed to…".

---

## Scope Check

~0.5 day. One new prompt constant, one Ollama call, ~15 lines of assembly + one small
truncation helper, plus a unit test. No new files, surfaces, tables, or schedules. No blockers —
all inputs (`summary`, `notes`, `isAvailable`, `generate`) already exist in `daily-summary.ts`.

| Piece | Effort |
|-------|--------|
| `LEAD_PROMPT` + `firstLine()` helper | Trivial |
| Generate + prepend + offline guard | Small |
| Unit test (truncation + offline skip) | Small |

---

## Open Questions

1. **Generate at midnight (daily-summary) or 6am (send-digest)?** Recommended: midnight, because that's where Ollama + note data already live and `send-digest.ts` has no Ollama import. Cost: the line reflects midnight's data, not anything captured 12am–6am (negligible — capture is light overnight). If we ever want it freshest, move the call into `send-digest.ts` (would add an Ollama dependency there).
2. **Prefix wording.** "Worth your attention:" vs. no prefix (let the sentence stand alone). Recommend the prefix for scannability; trivially tunable.
3. **Interaction with the future "Topics circling" section** (synthesis design): once that ships, the lead could be sourced from the most-active `topic_cluster` instead of a fresh Ollama call. Keep this version self-contained; swap the source later if synthesis lands.

---

## Related

- `docs/plans/2026-05-28-competitive-landscape-research.md` — Lesson #1 (origin)
- `src/workflows/daily-summary.ts` — where the lead is generated
- `src/workflows/send-digest.ts` — unchanged renderer (`digestToHtml`, `buildTrmnlPayload`)
- `docs/plans/2026-05-26-synthesis-retrieval-agent-design.md` — "Topics circling"; future source for the lead (Open Question 3)
- `docs/plans/2026-05-28-note-task-proposer-design.md` — sibling Ready doc (Lesson #6)
