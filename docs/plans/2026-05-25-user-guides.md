# User Guides Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a consolidated user-guide hub plus 5 per-capability feature guides, and wire a wrap-up trigger so future features get a guide by default.

**Architecture:** Hub + spokes. `docs/USER-EXPERIENCE.md` becomes the consolidated hub (retitled, links out). Five feature guides live in `docs/guides/features/`, all generated from one `_TEMPLATE.md`. Two checklist edits (design-doc Done criteria + GitOps docs stage) make guide creation a recurring habit.

**Tech Stack:** Markdown only. No code, no tests in the traditional sense — "verification" means each factual claim in a guide is checked against the real source (workflow file, launchd plist, design doc) before commit.

**Source of truth:** Design doc `docs/plans/2026-05-25-user-guides-design.md`.

---

## How to "test" a documentation task

There is no test runner. For each guide, the equivalent of "run the test" is:

1. Every workflow file / launchd agent / command named in the guide must actually exist — verify with `ls`, `grep`, or `Read`.
2. Every command in "Configure" / "Troubleshooting" must be runnable as written (check flags against the script).
3. No reference to archived features (anything under `archive/`, SeleneChat, SeleneMobile, threads).

If a claim can't be verified against a real file, cut it or mark it explicitly as TODO — never guess.

---

### Task 1: Create the guide template

**Files:**
- Create: `docs/guides/features/_TEMPLATE.md`

**Step 1: Create the directory and template**

Write `docs/guides/features/_TEMPLATE.md`:

```markdown
# <Feature Name>

**What this does for you:** <one plain-language sentence>
**Last Updated:** YYYY-MM-DD

## Using it

What you do, when, and what you look at. Operator-facing — this section comes first on purpose.

## How it works

What runs behind the scenes, on what schedule, where output lands. Name the workflow file(s) and launchd agent(s).

## Configure & customize

Knobs you can turn: env vars, file paths, schedule. Each with the exact file/command.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| <thing goes wrong> | <exact recovery command> |

## Related

- Design doc(s): `docs/plans/...`
- Connected guides: `...`
```

**Step 2: Verify**

Run: `ls docs/guides/features/_TEMPLATE.md`
Expected: file listed.

**Step 3: Commit**

```bash
git add docs/guides/features/_TEMPLATE.md
git commit -m "docs: add feature-guide template"
```

---

### Task 2: Write capturing-notes.md

**Files:**
- Create: `docs/guides/features/capturing-notes.md`
- Sources to read first: `src/workflows/ingest.ts`, `docs/guides/ios-shortcut-setup.md`, `docs/plans/2026-03-21-eink-notebook-ingestion-design.md`, `docs/plans/2026-03-18-physical-digital-bridge-design.md`, the e-ink WatchPaths launchd plist.

**Step 1: Gather source facts**

Read each source. Note the real ingest endpoint (`POST /webhook/api/drafts`, port 5678), duplicate detection behavior, each capture path (Drafts, iOS shortcut, e-ink OCR, whiteboard), and which launchd agent watches the e-ink folder.

**Step 2: Draft from template**

Fill all five sections. "Using it" = the four ways to get a note in. "How it works" = ingest endpoint + dedup + e-ink OCR (minicpm-v / pdftoppm) pipeline. Cross-link `docs/guides/ios-shortcut-setup.md` rather than duplicating its steps.

**Step 3: Verify every claim**

- `grep -n "webhook/api/drafts" src/server.ts` confirms endpoint.
- Confirm e-ink launchd plist exists in `launchd/`.
- No archived-feature references.

**Step 4: Commit**

```bash
git add docs/guides/features/capturing-notes.md
git commit -m "docs: add capturing-notes feature guide"
```

---

### Task 3: Write obsidian-library.md

**Files:**
- Create: `docs/guides/features/obsidian-library.md`
- Sources: `src/workflows/export-obsidian.ts`, `docs/plans/2026-03-21-obsidian-librarian-design.md`, `docs/plans/2026-03-21-obsidian-moc-design.md`, `launchd/com.selene.export-obsidian.plist`.

**Step 1: Gather source facts**

Note the vault output path, what gets generated (curated notes, topic indexes, 8-category MOCs, Dashboard.md), and the hourly schedule.

**Step 2: Draft from template**

"Using it" = where the vault is, what to browse, the dashboard. "How it works" = `export-obsidian.ts`, hourly via `com.selene.export-obsidian`, LLM curation. "Configure" = vault path / schedule. "Troubleshooting" = regenerate command `npx ts-node src/workflows/export-obsidian.ts`.

**Step 3: Verify**

- `grep -n -i "vault\|obsidian" src/lib/config.ts` (or wherever the path is set) confirms output path.
- Confirm `launchd/com.selene.export-obsidian.plist` exists and is hourly.

**Step 4: Commit**

```bash
git add docs/guides/features/obsidian-library.md
git commit -m "docs: add obsidian-library feature guide"
```

---

### Task 4: Write daily-digest.md

**Files:**
- Create: `docs/guides/features/daily-digest.md`
- Sources: `src/workflows/daily-summary.ts`, `src/workflows/send-digest.ts`, `docs/plans/2026-02-12-apple-notes-daily-digest-design.md`, `launchd/com.selene.daily-summary.plist`, `launchd/com.selene.send-digest.plist`.

**Step 1: Gather source facts**

Note: summary generated at midnight, digest delivered to pinned Apple Note "Selene Daily Digest" at 6am. Two workflows, two launchd agents — present as ONE capability.

**Step 2: Draft from template**

"Using it" = open Apple Notes 6am, find pinned note (reuse the existing wording from `USER-EXPERIENCE.md` morning section). "How it works" = `daily-summary.ts` midnight → `send-digest.ts` 6am. "Troubleshooting" = `npx ts-node src/workflows/send-digest.ts` to regenerate.

**Step 3: Verify**

- Confirm both launchd plists exist and their schedules (midnight / 6am).
- Confirm the Apple Note title string matches what `send-digest.ts` actually writes.

**Step 4: Commit**

```bash
git add docs/guides/features/daily-digest.md
git commit -m "docs: add daily-digest feature guide"
```

---

### Task 5: Write folio-delivery.md

**Files:**
- Create: `docs/guides/features/folio-delivery.md`
- Sources: `src/workflows/send-ipad.ts` (and Kindle equivalent if separate), `docs/plans/2026-05-25-folio-ipad-delivery-design.md`. Also fold in the `project_folio_delivery` memory quirks (ports, dark-mode fix) — but verify each against the code before stating it.

**Step 1: Gather source facts**

Note the iPad flow (QR via qrcode-terminal → LAN reader → Apple Pencil annotation → feedback), the Kindle flow, port specifics, and the dark-mode fix.

**Step 2: Draft from template**

"Using it" = run the command, scan QR on iPad, annotate, feedback returns. "How it works" = `send-ipad.ts`, LAN reader, feedback path. "Configure" = ports. "Troubleshooting" = the port/dark-mode quirks.

**Step 3: Verify**

- Read `src/workflows/send-ipad.ts`; confirm the QR library, port, and feedback path before stating them.
- Do NOT copy memory claims verbatim — confirm each against current code.

**Step 4: Commit**

```bash
git add docs/guides/features/folio-delivery.md
git commit -m "docs: add folio-delivery feature guide"
```

---

### Task 6: Write agent-enrichments.md

**Files:**
- Create: `docs/guides/features/agent-enrichments.md`
- Sources: `docs/plans/2026-05-23-agent-layer-design.md`, the agent-layer source dir (BaseAgent, Things enricher, ActionExecutor, dashboard), `launchd` agent for 9am/6pm schedule.

**Step 1: Gather source facts**

Note: 4 SQLite tables, BaseAgent + Things enricher, ActionExecutor, dashboard (4 views), Apple Notes + Obsidian delivery, runs 9am/6pm. Identify the actual source paths (grep for the agent code).

**Step 2: Draft from template**

"Using it" = where proposed Things enrichments show up, how to act on them. "How it works" = agent layer tables + enricher + executor + dashboard, 9am/6pm. "Configure" = schedule. "Troubleshooting" = how to re-run / inspect the dashboard.

**Step 3: Verify**

- `grep -rn "enricher\|BaseAgent\|ActionExecutor" src/` confirms the code exists and paths are right.
- Confirm the launchd schedule.

**Step 4: Commit**

```bash
git add docs/guides/features/agent-enrichments.md
git commit -m "docs: add agent-enrichments feature guide"
```

---

### Task 7: Convert USER-EXPERIENCE.md into the consolidated hub

**Files:**
- Modify: `docs/USER-EXPERIENCE.md`

**Step 1: Retitle**

Change the H1 from `# Using Selene — A Daily Guide` to `# Selene User Guide`. Keep the subtitle/intro.

**Step 2: Add a "Feature Guides" section**

Near the top (after the core-loop overview), add a section linking to each feature guide with its one-line "what this does for you":

```markdown
## Feature Guides

Each feature has its own guide — how you use it, how it works, and how to fix it when it breaks.

- [Capturing notes](guides/features/capturing-notes.md) — every way a thought gets into Selene.
- [Obsidian library](guides/features/obsidian-library.md) — your curated, browsable vault.
- [Daily digest](guides/features/daily-digest.md) — the 6am Apple Notes summary.
- [Folio delivery](guides/features/folio-delivery.md) — read & annotate on iPad/Kindle.
- [Agent enrichments](guides/features/agent-enrichments.md) — proposed upgrades to your Things tasks.
```

**Step 3: Verify**

- Each relative link resolves: `ls docs/guides/features/<each>.md`.
- Daily-loop narrative still reads top-to-bottom.

**Step 4: Commit**

```bash
git add docs/USER-EXPERIENCE.md
git commit -m "docs: make USER-EXPERIENCE.md the consolidated user-guide hub"
```

---

### Task 8: Add the docs/INDEX.md pointer

**Files:**
- Modify: `docs/INDEX.md`

**Step 1: Add row to the Directory Structure table**

Add under `guides/`:

```markdown
| `guides/features/` | Per-capability user guides (how to use each feature). Hub: `USER-EXPERIENCE.md` |
```

And add to Quick Links:

```markdown
- **Feature guides:** `guides/features/`
```

**Step 2: Verify**

`grep -n "features" docs/INDEX.md` shows both additions.

**Step 3: Commit**

```bash
git add docs/INDEX.md
git commit -m "docs: link feature guides from docs index"
```

---

### Task 9: Wire the wrap-up trigger

**Files:**
- Modify: `docs/plans/INDEX.md` (Done criteria)
- Modify: `templates/BRANCH-STATUS.md` (Docs stage, line ~42-46)

**Step 1: Add the Done-criteria question**

In `docs/plans/INDEX.md`, under the "A design is 'Ready' when it has" block (or a new note near the Done table), add:

```markdown
**Before moving a design to "Done":** Did this add or change something you interact with?
- **Yes** → create or update the matching `docs/guides/features/*.md` + add/update its link in `USER-EXPERIENCE.md`.
- **No** (invisible refactor/infra) → note "no user-facing change."
```

**Step 2: Add the BRANCH-STATUS docs checkbox**

In `templates/BRANCH-STATUS.md` under `### Docs`, add:

```markdown
- [ ] User-facing change? If yes: feature guide created/updated + hub link added
```

**Step 3: Verify**

`grep -n "feature guide\|user-facing" templates/BRANCH-STATUS.md docs/plans/INDEX.md` shows both edits.

**Step 4: Commit**

```bash
git add docs/plans/INDEX.md templates/BRANCH-STATUS.md
git commit -m "docs: add user-guide wrap-up trigger to Done criteria and GitOps docs stage"
```

---

### Task 10: Final verification

**Step 1: Confirm all deliverables exist**

```bash
ls docs/guides/features/
grep -c "guides/features" docs/USER-EXPERIENCE.md
```
Expected: `_TEMPLATE.md` + 5 guides; ≥5 link matches in the hub.

**Step 2: Check for archived-feature leakage**

```bash
grep -rin "selenechat\|selenemobile\|thread" docs/guides/features/
```
Expected: no matches (or only deliberate, verified ones).

**Step 3: Move design doc to Done**

Update `docs/plans/INDEX.md`: move the user-guides row from Ready to Done. Commit.

---

## Mark complete

Update `.claude/PROJECT-STATUS.md` with the user-guides addition, then run verification-before-completion before claiming done.
