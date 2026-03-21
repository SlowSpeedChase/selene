# Obsidian Maps of Content Design

**Status:** Ready
**Date:** 2026-03-21

## Problem

The Obsidian export produces 134 unique themes for 133 notes — nearly every note gets its own theme. This means:
- Only 2 topic pages get generated (need 2+ notes per theme)
- The dashboard LLM hallucinates link names, creating 0-byte stub files in the vault
- No meaningful Maps of Content exist for navigating the library

## Solution

Replace freeform themes with 8 fixed categories. The local LLM assigns each note to one primary category and optionally cross-references 1-2 others. MOC pages organize notes into named sub-sections. A code-generated dashboard links to MOCs (no LLM = no hallucinated links).

## Design Decisions

- **Fixed categories defined in code** — the 7b model needs guardrails for consistency
- **Primary + cross-references** — each note lives in one MOC but is discoverable from related MOCs via "See Also"
- **Named sub-sections** within MOCs — the LLM groups notes under headers like `## Dating`, `## Family`
- **Garden only when new notes exported** — skip MOC rebuild if nothing changed
- **Code-generated dashboard** — no LLM involvement, guaranteed real links only
- **Local LLM reads all note content** — no cloud API involvement in categorization

## Categories

| Category | Covers |
|---|---|
| Personal Growth | self-reflection, identity, emotional processing, therapy |
| Relationships & Social | dating, social skills, parties, family, feeling seen |
| Health & Body | nutrition, fitness, meal planning, pet care |
| Projects & Tech | Selene, coding, AI tools, software ideas |
| Career & Work | job stress, career pivots, income, professional identity |
| Creativity & Expression | writing, blogging, teaching, music, art |
| Politics & Society | civic engagement, urban planning, economics, media critique |
| Daily Systems | productivity, routines, time management, organization |

## Data Model

Add two columns to `processed_notes`:

```sql
ALTER TABLE processed_notes ADD COLUMN category TEXT;
ALTER TABLE processed_notes ADD COLUMN cross_ref_categories TEXT;  -- JSON array
```

`primary_theme` remains as a freeform 2-4 word descriptor (useful for sub-section labels).

## Prompt Changes

### Extract Prompt (process-llm.ts)

Add the 8 categories to the prompt. LLM picks `category` (constrained) and `cross_ref_categories` (0-2 others). Tighten `primary_theme` to 2-4 words. Drop `secondary_themes` (replaced by cross-refs).

### New MOC Prompt (export-obsidian.ts)

Per-category prompt that receives all notes in that category plus cross-referenced notes. LLM produces:
1. 2-3 sentence intro in second person
2. Named sub-sections (`##` headers) grouping notes by theme
3. Notes listed as `- [[{filename}]] — one-line description`
4. "See Also" section for cross-referenced notes
5. Links to related category MOCs

Rules enforced in prompt:
- Use `[[filename]]` exactly as provided — never invent link names
- Every note in exactly one sub-section
- Sub-section names 1-3 words
- Merge sub-sections with only 1 note into related sub-sections

### Dashboard (code-generated, no LLM)

```
# Selene Library

## Your Maps of Content
| Category | Notes | Last Activity |
| [[Personal Growth]] | 24 | 2026-03-19 |
...

## Recently Captured
- [[filename]] — essence (last 10 notes)

## Quiet Areas
Categories with no notes in the last 30 days.
```

## Vault Structure

```
vault/Selene/
  Dashboard.md                    -- code-generated navigation hub
  Maps/
    Personal Growth.md            -- MOC with sub-sections
    Relationships & Social.md
    Health & Body.md
    Projects & Tech.md
    Career & Work.md
    Creativity & Expression.md
    Politics & Society.md
    Daily Systems.md
  Notes/
    2025-07-19-i-want-to-meet-a-partner.md  -- individual notes (unchanged)
```

Old `Selene/Topics/` directory is deprecated and removed.

## Backfill Strategy

One-time script (`scripts/backfill-categories.ts`):

1. Query all `processed_notes` where `category IS NULL`
2. For each, send existing metadata (title, primary_theme, essence, concepts) through a lightweight categorization prompt — no need to re-read full note content
3. Save `category` and `cross_ref_categories` to new columns
4. Reset `exported_to_obsidian = 0` on all notes so next export rebuilds MOCs
5. Delete 0-byte stub files in vault root
6. Remove old `Selene/Topics/` directory

## Files Changed

- `src/lib/prompts.ts` — updated extract prompt, new MOC prompt, remove dashboard prompt
- `src/workflows/process-llm.ts` — save category + cross_ref_categories to new columns
- `src/workflows/export-obsidian.ts` — new MOC generation in `Selene/Maps/`, code-generated dashboard, conditional gardening (skip if no new notes)
- New: `scripts/backfill-categories.ts` — one-time migration

## Future Improvements

- Sub-sections only when 3+ notes (currently all sub-sections are named regardless of count)
- LLM-driven sub-cluster discovery as local models improve
- Category suggestions when the LLM is uncertain about fit

## ADHD Check

- Dashboard is scannable — table format, no walls of text
- MOCs group related notes visually — "out of sight, out of mind" is addressed
- Cross-references surface notes you'd otherwise forget about
- Quiet Areas nudge gently without guilt
