# Design: Obsidian Feedback Loop — "Your note"

**Date:** 2026-06-10
**Status:** Ready (Phase 1)
**Depends on:** Fact store Ph1+Ph2 (LIVE — `facts.db`/`selene.db` split, pending = derivation-absence), Obsidian export (`export-obsidian.ts` / `obsidian-render.ts`), Knowledge Constellation Phase A (ExcaliBrain browse is the surface this serves)
**Related:** [[2026-05-31-fact-store-design]] (Ph3 `category_overrides` — see "Relationship to category_overrides" below), [[2026-05-29-knowledge-constellation-design]], [[2026-05-31-sub-categories-design]]

---

## What & why

When browsing the vault (ExcaliBrain on Mac or iPad), a note's filing sometimes **misses the author's intent**. Motivating example: *"I loved and was really good at diagraming sentences in English class"* was filed by its **surface topic** (theme `Academic Achievement`, parents `Learning`/`Personal Growth`). What the author meant was its **function**: "this is a skill I possess and enjoy — remember it for later." That distinction — a strengths-inventory entry, not a school memory — is invisible to the classifier because only the author knows it.

Today there is **no path to say so**. The vault is one-way (Selene → Obsidian); hand-edits get overwritten by the hourly export; fact-store Phase 3 reserved a `category_overrides` table but explicitly notes *"no correction UI/route exists — a real correction path is the feature."*

**This design adds that path:** free-text intent feedback, written directly in the note you're looking at, that (a) re-derives that note's filing with the intent as context, and (b) accumulates into few-shot examples so future notes get filed by function, not just surface topic.

### Named assumptions (decisions, not omissions)
- **Feedback is free text, not a structured re-tag.** The category swap *falls out of* the intent ("a skill I enjoy" → re-files itself); a structured picker could never express the intent. Confirmed with the user 2026-06-10.
- **Capture happens in the note file itself** (a marked section), because the vault is iCloud-synced — the same flow works on Mac and iPad with zero app-switching. Rejected: PKM-dashboard form (breaks the browse flow), handwriting via SeleneMarkup (breaks the browse flow, switch apps + re-find the note).
- **Feedback re-derives; it does not pin.** The LLM re-files with the author's words as strong context. A hard pin ("this category, forever") remains Ph3 `category_overrides` if ever needed — see below.

---

## Approach

**Approach A (chosen): a new `vault-feedback` scan workflow + a precious `note_feedback` table, with re-filing via the existing derivation-absence machinery.**

Two rejected alternatives, recorded so they are not re-litigated:
- **B — feedback as a linked captured note** (reuse the SeleneMarkup `source_note_id` annotation pattern). Maximum ingest reuse, but semantically wrong: feedback is metadata *about* a note, not a note. It would itself get classified/clustered/exported, polluting the graph, and re-filing would need awkward joins.
- **C — PKM dashboard correction form** (`/pkm/*`). Cleanest data path, but breaks the exact flow that motivates the feature: you are in ExcaliBrain on the iPad; switching to a browser and re-finding the note fails the friction test.

### Why A is cheap: the fact-store split already did the hard work

- **Re-filing is a one-line status flip, not a feature.** "Pending" is derivation-absence (fact-store Ph1). Setting the note's `note_state.status` back to `'pending'` makes the existing 5-minute `process-llm` agent re-derive it (`INSERT OR REPLACE` overwrites the old derivation). No new re-processing code path. (See §3 for why the flip beats the design's original row-delete.)
- **Durability is solved by address.** Human words are precious → `note_feedback` lives in `facts.db`, keyed on `captured_notes.id` (see §2 correction). A `rebuild` wipes all derived data and re-derives every note **with its feedback context already in the prompt** — corrections survive by construction, no merge step.

### Relationship to fact-store Ph3 `category_overrides`

This design **delivers the spirit of Ph3** (a real human-correction path, precious-side storage) with a richer shape: free-text intent instead of a category enum. It does **not** implement the hard-pin semantics (an override that wins regardless of what the LLM thinks). If re-derivation with intent context proves insufficiently obedient in practice, `category_overrides` remains the escalation — and `note_feedback.original_filing` snapshots will tell us how often the LLM disobeys. Ph3 stays on the books, demoted from "the correction feature" to "the pin, if needed."

---

## Phase 1 — the loop (capture → store → re-derive → visible ✓)

### 1. The capture surface: a `## ✍️ Your note` section

Every exported note ends with a `## ✍️ Your note` section — **empty by default** (an invitation, not a chore). The user types plain text under it, on Mac or iPad (Obsidian iPad supports keyboard and Pencil/Scribble).

After processing, the user's words are re-rendered as an **applied block**:

```markdown
## ✍️ Your note

> This is a skill I possess and enjoy using — I wanted to remember it for later.
> — applied 2026-06-10 ✓
```

**Parse rule (the whole protocol):** within the section, anything *inside* an applied block (blockquote ending in an `— applied … ✓` line) is history; any *other* non-whitespace text is **new feedback**. Multiple rounds accumulate as successive applied blocks.

### 2. File → note identity: `selene_id` frontmatter

`obsidian-render.ts` adds `selene_id: <captured_notes.id>` to frontmatter. This changes every note's content hash once → a one-time full re-render (the churn guard's job is preventing *pointless* churn; this one is load-bearing).

> **Plan-time correction (2026-06-10):** the design originally keyed on `source_uuid`, but older notes have NULL `source_uuid` (the Drafts UUID fix was recent), so it can't be the key. `captured_notes.id` is total AND equally stable: `facts.db` is precious — `rebuild` never touches it, and the fact-store migration was id-preserving.

### 3. New workflow: `src/workflows/vault-feedback.ts`

Scheduled via a new `com.selene.prod.vault-feedback` launchd agent, **every 15 minutes**. Each run:

1. **Scan** all of `Notes/*.md` (no mtime watermark — ~300 small files is trivially cheap, and the dedupe check below makes full rescans idempotent; less state, no lost-watermark edge case. *Plan-time simplification 2026-06-10.*)
2. **Parse** each file's `## ✍️ Your note` section by the rule above.
3. For each piece of new feedback:
   - Map file → note via `selene_id` frontmatter, validated against `facts.captured_notes`.
   - **Insert into `note_feedback` (`facts.db`)** — skipping if an identical `(raw_note_id, feedback_text)` row exists (idempotency: ingested-but-not-yet-re-exported text will be seen again next scan).
   - Snapshot the current filing (`theme`, `concepts`, `category`, `cross_ref_categories`, `sub_categories`, essence) into `original_filing` — Phase 2's few-shot raw material, captured *before* the next step replaces it.
   - **Re-pend the note: `setNoteState(status: 'pending', processed_at: null)`** → `process-llm` re-derives within ~5 min (its writes are `INSERT OR REPLACE`, so the old derivation is overwritten cleanly). *Plan-time correction (2026-06-10): the design originally said "delete the `processed_notes` + `note_embeddings` rows," but the status flip is strictly safer — it preserves the unrelated `note_state` bookkeeping (`status_folio`, `inbox_status`) that row deletion via `note_state` removal would have lost, and the existing pending-query machinery (`COALESCE(ns.status,'pending')`) handles the rest.* Downstream (synthesis clusters, export) refresh on their own schedules.

```sql
-- facts.db (precious, Time-Machine-backed, survives rebuild)
CREATE TABLE note_feedback (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  raw_note_id     INTEGER NOT NULL,     -- captured_notes.id (stable: facts.db is never rebuilt)
  feedback_text   TEXT NOT NULL,
  original_filing TEXT,                 -- JSON snapshot of the filing being corrected
  created_at      DATETIME NOT NULL,
  applied_at      DATETIME              -- set when the re-derivation lands
);
```

### 4. Prompt injection: the re-file

`process-llm.ts`, while building a note's prompts, checks `note_feedback` for the note id. If rows exist, `EXTRACT_PROMPT` and the essence prompt gain a block:

> The author has clarified what this note means to them: «…all feedback texts, oldest first…». Weight the author's stated intent over the surface topic when choosing theme, concepts, and category.

On successful processing of a note with pending feedback, `applied_at` is stamped. The diagramming note re-derives as something like theme `Personal Strengths`, concepts about skills/enjoyment — and because this runs inside normal processing, **every future re-derivation (including `rebuild`) carries the intent automatically.**

### 5. Exporter changes (`export-obsidian.ts` / `obsidian-render.ts`)

- Emit `selene_id` frontmatter (§2).
- Render the `## ✍️ Your note` section: empty, or with applied blocks from `note_feedback` (DB is the source of truth once ingested).
- **Preserve-on-render (mandatory):** before overwriting a note file, read its existing section; any *unprocessed* user text (per the parse rule) is re-emitted verbatim below the rendered applied blocks. The hourly export can therefore never clobber feedback the scanner hasn't ingested yet, regardless of run ordering.
- The content hash covers the full rendered output including applied blocks, so the "✓" state writes exactly once and then goes quiet.

### Error handling

- **Unmatched file** (no `selene_id`, or an id not present in `captured_notes` — e.g. a hand-created note): skip + log. Never delete or modify.
- **Whitespace-only / empty section:** not feedback.
- **iCloud conflict copies** (`… 2.md`): they carry the same `selene_id` as the original, but identical text dedupes and differing text in two copies is rare enough to accept; conflict copies otherwise behave as normal files. (Vault-level conflict hygiene is out of scope.)
- **Re-derivation fails** (Ollama down / parse failure): the note simply stays pending — the existing retry semantics of derivation-absence apply; feedback is already safe in facts.

---

## Phase 2 — learning for future notes (small, separate plan)

The classification prompt (`EXTRACT_PROMPT`) gains a corrections block: the **~5 most recent applied corrections**, each rendered as *original text (truncated) → original filing → what the author said → corrected filing* (corrected filing read from the note's current `processed_notes` row at prompt-build time). Capped and recency-ordered to respect mistral:7b's context window. Ships only after Phase 1's loop is proven on real corrections — the accumulated `note_feedback` rows are the training set, so Phase 1 is generating Phase 2's input from day one.

Out of scope for Phase 2 (deliberately): weighting corrections by similarity to the incoming note (embedding-match few-shot selection). Recency-N first; get fancy only if the simple version misses.

---

## Testing

All dev-sandbox (`resolveVaultPath` already isolates the dev vault; dev DB is `~/selene-data-dev`):

- **Jest:** section parser (empty / new text / applied blocks / mixed / whitespace), uuid + filename-fallback mapping, idempotent re-scan (no duplicate rows), preserve-on-render (unprocessed text survives an export), delete-makes-pending round trip, prompt-injection block presence, applied-block render.
- **e2e (dev batch):** seed a dev note → export → append feedback text to the vault file → run `vault-feedback` → run `process-llm` → assert new filing + `applied_at` + re-export shows the ✓ block.
- **launchd sync:** new plist + `install-launchd.sh` entry + SYSTEM-MAP regeneration (the launchd-auditor checklist).

---

## Acceptance Criteria (Phase 1)

- [ ] Every exported note carries `selene_id` frontmatter and a `## ✍️ Your note` section.
- [ ] Text typed under the section lands in `facts.db note_feedback` (with `original_filing` snapshot) within one scan cycle, and the note is re-derived with the intent in-prompt within ~20 min end-to-end.
- [ ] The next export shows the new filing AND the feedback as an applied-✓ block; the user's words are never lost by any export/scan ordering (preserve-on-render test proves it).
- [ ] Feedback survives `rebuild`: post-rebuild, the note's derivation reflects the intent without any manual step.
- [ ] Unmatched files, whitespace, and iCloud conflict copies are skipped with a log, never modified.
- [ ] Dev-sandbox e2e green; jest suite green; launchd plist/install/SYSTEM-MAP in sync.

### ADHD check
- **Reduces friction:** feedback is typed exactly where you already are (the note, on the device in your hand) — no app switch, no form, no naming the note.
- **Visible:** the applied-✓ block externalizes "did it hear me?" — the loop closes in the same place it opened.
- **Externalizes cognition:** "what I actually meant" stops being a thing you must remember to re-explain; it's stored once, applied forever (every re-derivation, every rebuild).
- **No nagging:** the empty section is an invitation; nothing prompts, counts, or expires.

### Scope check
- **Phase 1 < 1 week:** one new workflow + one facts table + a render section + a prompt block + one plist. Reuses process-llm, export, launchd, and rebuild machinery untouched-or-lightly-touched.
- **Phase 2 ≈ 1–2 days**, gated on Phase 1 data existing.
