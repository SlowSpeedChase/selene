# User Guides — Design

**Status:** Ready
**Date:** 2026-05-25
**Topic:** documentation, user-guides, process

---

## Problem

Selene's features are documented for *building* (design docs in `docs/plans/`) and for *setup* (`docs/guides/`), but there's no consistent guidance for *using* each feature day-to-day. The single daily-use doc (`USER-EXPERIENCE.md`) is good but doesn't go deep per feature, and nothing in the workflow prompts a guide to be written when development wraps up. The result: features ship and the "how do I actually use this / how does it work" knowledge lives only in the author's head or scattered design docs.

## Goal

1. A **consolidated user guide** (hub) that gives the daily-use narrative and links out to per-feature depth.
2. **One guide per user-facing capability**, each covering both how *you* use it and how it *works* / troubleshooting.
3. A **wrap-up trigger** so every future feature either gets a guide or consciously skips it — making this a habit, not a one-time effort.

## Non-Goals

- Guides for invisible/background workflows you don't interact with (`process-llm.ts`, `distill-essences.ts`) — their mechanics live inside the relevant feature guide's "How it works" section.
- Guides for archived features (SeleneChat, SeleneMobile, threads, etc.) or pure refactors (codebase-simplification, remove-n8n-naming).
- API/developer reference docs — that's `docs/architecture/`.

---

## Design

### Granularity: per user-facing capability

The unit is "a thing you interact with," not "a design doc" (69 exist, most archived) and not "a workflow file" (splits experiences like the digest across two files). This maps the ~5 living capabilities to ~5 guides and makes the wrap-up trigger clean.

### Layout (Approach A — Hub + spokes)

```
docs/
├── USER-EXPERIENCE.md            ← CONSOLIDATED HUB (heading retitled "Selene User Guide")
│                                   keeps daily-loop narrative + links to each feature guide
└── guides/
    └── features/                 ← per-capability guides
        ├── _TEMPLATE.md
        ├── capturing-notes.md
        ├── obsidian-library.md
        ├── daily-digest.md
        ├── folio-delivery.md
        └── agent-enrichments.md
```

- Existing `docs/guides/` setup/operational files stay put; feature guides live in the `features/` subfolder so the two kinds don't mix.
- `docs/INDEX.md` gets one new pointer to `guides/features/`.
- File path `USER-EXPERIENCE.md` is kept (avoids breaking links); only the internal heading changes.

Hub + spokes mirrors the existing `docs/plans/INDEX.md` pattern: one "where do I start" answer, detail in focused linkable files. Avoids a competing third consolidated doc that would drift.

### Guide template (`_TEMPLATE.md`)

Each guide serves both audiences in one file, operator-facing content first (the 6am question is "what do I do," not "which file generates this"):

```markdown
# <Feature Name>

**What this does for you:** <one sentence, plain language>
**Last Updated:** YYYY-MM-DD

## Using it
Daily touchpoints — what you do, when, what you look at.

## How it works
What runs behind the scenes, on what schedule, where output lands.
Names the workflow file + launchd agent.

## Configure & customize
Knobs you can turn: env vars, file paths, schedule.

## Troubleshooting
| Symptom | Fix |
Common failures + exact recovery command.

## Related
- Design doc(s) in docs/plans/
- Connected feature guides
```

### Backfill set (~5 guides)

| Guide | Covers | Source workflows / design docs |
|-------|--------|--------------------------------|
| `capturing-notes.md` | Drafts, iOS shortcut, e-ink notebook OCR, whiteboard capture | `ingest.ts`, `ios-shortcut-setup.md`, eink-notebook-ingestion + physical-digital-bridge docs |
| `obsidian-library.md` | Curated vault: notes, topic indexes, MOCs, dashboard | `export-obsidian.ts`, obsidian-librarian + obsidian-moc docs |
| `daily-digest.md` | 6am Apple Notes digest | `daily-summary.ts` + `send-digest.ts`, apple-notes-daily-digest doc |
| `folio-delivery.md` | iPad (QR → annotate) + Kindle folio delivery | `send-ipad.ts`, folio-ipad-delivery doc |
| `agent-enrichments.md` | Agent layer proposing Things task enrichments | agent-layer-design doc |

### Wrap-up trigger

Two lightweight gates make guide creation a habit:

1. **Design-doc Done criteria** (`docs/plans/INDEX.md`): a doc can't move to **Done** until answering — *Did this add or change something you interact with?* Yes → create/update the matching feature guide + hub link. No → note "no user-facing change" and move on.

2. **GitOps `docs` stage** (`BRANCH-STATUS.md` template): add one checkbox —
   `- [ ] User-facing change? If yes: feature guide created/updated + hub link added`

Phrasing as a *question* (not "always write a guide") is the filter that keeps it sustainable.

---

## Acceptance Criteria

- [ ] `docs/guides/features/_TEMPLATE.md` exists with the agreed structure.
- [ ] 5 feature guides written from the template, each with all sections populated from real content.
- [ ] `USER-EXPERIENCE.md` retitled "Selene User Guide" and links to all 5 feature guides.
- [ ] `docs/INDEX.md` points to `guides/features/`.
- [ ] `docs/plans/INDEX.md` Done criteria include the user-facing-change question.
- [ ] `BRANCH-STATUS.md` template (`templates/`) has the docs-stage checkbox.

## ADHD Check

- Reduces friction: one hub answers "what do I do today," guides answer "how do I use X" without digging through code or design docs.
- Visible: knowledge externalized into files instead of held in the author's head.
- Operator-first ordering keeps the daily-use answer above the fold.

## Scope Check

~5 guides + template + hub edit + two checklist edits. Well under a week.
