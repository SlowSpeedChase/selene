# Act 0 — The Daily Gift

**Status:** Ready
**Created:** 2026-06-13
**Topic:** executive-function, worksheet, attention-log, ipad, habit

---

## Problem

Selene files notes well but never resurfaces them. A want and a passing thought are
indistinguishable; nothing comes back without active search. The deeper problem is habit
before features — a perfect system you never open is worthless. Act 0 establishes the
daily touchpoint and the attention dataset that everything else in the executive-assistant
vision builds on.

---

## Solution

Graft a small "things I noticed for you" section onto the existing daily worksheet. ≤3
surfaced notes, framed as a gift not a duty, with four guilt-free reaction taps. Every
tap writes to a new `attention_log` table — the raw material for salience scoring and,
eventually, Act 1's want-coalescence.

**Framing is load-bearing:** never "your review queue," always "things I noticed for you."

---

## Design

### Option chosen: gift items as first-class worksheet fields (Option A)

Gift items are a new `WorksheetFieldKind = 'gift_surface'` alongside the existing
`free_capture` and `note_review`. Taps are a new `ChosenAction = 'react'`, submitted
bundled with the rest of the worksheet. No separate endpoint needed.

---

### Schema — `facts.db`

One new table (precious — taps are human decisions that survive `rebuild`):

```sql
CREATE TABLE attention_log (
  id           INTEGER PRIMARY KEY,
  worksheet_id TEXT NOT NULL,   -- e.g. "ws_2026-06-13"
  note_id      INTEGER NOT NULL, -- captured_notes.id
  slot_role    TEXT NOT NULL,   -- buried_treasure | connection | heating_up
  reaction     TEXT NOT NULL,   -- important | keep | not_now | let_go
  reacted_at   TEXT NOT NULL    -- ISO timestamp
);
CREATE INDEX attention_log_note_id ON attention_log(note_id);
CREATE INDEX attention_log_reacted_at ON attention_log(reacted_at);
```

**Salience score** — computed on-the-fly, no stored column:

```
score = engagement_count / (hours_since_last_reaction + 2) ^ 1.5
```

`engagement_count` = count of non-`let_go` reactions for the note. Cold start: score
is 0 everywhere; slots fall back to recency/random.

---

### Type extensions — `src/types/worksheets.ts`

```typescript
export type WorksheetFieldKind = 'free_capture' | 'note_review' | 'gift_surface';
export type GiftSlotRole = 'buried_treasure' | 'connection' | 'heating_up';
export type ChosenAction = 'new_note' | 'acknowledge' | 'react';
export type GiftReaction = 'important' | 'keep' | 'not_now' | 'let_go';

export interface GiftItem {
  noteId: number;
  title: string;
  snippet: string;
  date: string;             // YYYY-MM-DD
  slotRole: GiftSlotRole;
  connectionNote?: {        // only present on 'connection' slot
    noteId: number;
    title: string;
  };
}

// WorksheetField gains:
//   gifts?: GiftItem[]          (on gift_surface fields)
//   binding.action: 'react'     (new action kind)

// WorksheetAnswer gains:
//   noteId?: number             (which gift card was reacted to)
//   reaction?: GiftReaction     (which button was tapped)
```

---

### Slot selection — `generate-worksheet.ts`

The `gift_surface` field is always **first** in the `fields` array. Slots:

| Slot | Query strategy | Cold-start fallback |
|---|---|---|
| **buried_treasure** | Random note older than 14 days with zero `attention_log` entries | Random note older than 14 days (any) |
| **connection** | Highest-similarity `note_connections` pair: one note ≤7 days old, other ≥14 days old | Omit slot (≤2 items is fine) |
| **heating_up** | Most recently created note with no `attention_log` entry | Most recently created note |

Notes already reacted to are excluded via `LEFT JOIN attention_log WHERE al.id IS NULL`.
Once the log fills, slot queries weight candidates by salience score — no behavior change
until data exists.

---

### Submission — `applyWorksheetAnswers`

- `chosenAction: 'react'` answers write one row to `attention_log` per reacted card
- Skipped cards (no tap) write nothing — a non-reaction is not a reaction
- Existing `new_note` and `acknowledge` paths unchanged

---

### iPad UI — SeleneMarkup

**New component: `GiftSurfaceView`**

Renders above the pencil fields. Each card:

```
┌─────────────────────────────────────────────────────┐
│  buried treasure · 3 weeks ago                      │
│                                                      │
│  "want to host a dinner party for improv people"     │
│                                                      │
│  [ Important ]  [ Keep ]  [ Not now ]  [ Let go ]   │
└─────────────────────────────────────────────────────┘
```

- Slot role label above the note text (small, muted)
- Connection slot: both note titles with `↔` between them
- Tap button selects (highlighted); tap again deselects (no reaction = fine)
- Reactions included in the `WorksheetAnswer` array on submit

**Integration:** the existing `WorksheetView` field-type switch gains a `.gift_surface`
case rendering `GiftSurfaceView`. Submit button collects all answers including reactions
— no other changes to the submission flow.

The existing `free_capture` field ("Anything on your mind?") already serves as the
capture box — no new field needed.

---

## Acceptance Criteria

- [ ] `GET /api/worksheets/today` returns a `gift_surface` field first, with ≤3 items
      via the three slot roles (buried_treasure, connection, heating_up)
- [ ] Cold start (empty attention_log + no note_connections pairs) works without errors:
      buried_treasure and heating_up fall back to random/recency; connection slot omitted
- [ ] `POST /api/worksheets/:id/answers` with `react` answers writes to `attention_log`
      in `facts.db`; skipped cards write nothing
- [ ] Reacted notes are excluded from future slot selection
- [ ] Salience score increases for notes tapped `important`/`keep`; `let_go` excluded
      from engagement_count
- [ ] iPad: `GiftSurfaceView` renders above pencil fields; all 4 tap buttons work;
      reactions submit with the worksheet
- [ ] ADHD framing correct: label reads "things i noticed for you" (or equivalent),
      not "review queue"

---

## ADHD Design Check

- [x] **Reduces friction?** ≤3 items, ~30s, taps-only, no required interaction
- [x] **Visible?** First thing you see on the worksheet; gift framing creates pull not duty
- [x] **Externalizes cognition?** System holds what's worth revisiting; no mental tracking

---

## Scope

**In scope (Act 0):**
- `attention_log` table in `facts.db`
- Type extensions in `worksheets.ts`
- Slot selection logic in `generate-worksheet.ts`
- `react` answer handling in `applyWorksheetAnswers`
- `GiftSurfaceView` in SeleneMarkup

**Out of scope (Act 1+):**
- Want coalescence / named wants
- Cloud LLM planning
- EventKit / Reminders handoff
- Chat interface

---

## Links

- **Parent design:** `docs/plans/2026-06-07-executive-assistant-wants-design.md`
- **Branch:** `feat/act0-daily-gift` (added when implementation starts)
- **PR:** (added when complete)
- **Affected:** `src/types/worksheets.ts`, `src/workflows/generate-worksheet.ts`,
  `src/routes/worksheets.ts`, `facts.db` schema, `~/SeleneMarkup`
