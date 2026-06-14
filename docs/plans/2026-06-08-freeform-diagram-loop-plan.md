# Freeform ⇄ Repo Visual Thinking Loop — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stand up an ongoing loop where the user sketches Selene's design on iPad in Apple Freeform, exports PNGs to an iCloud inbox, and Claude reads them and gives back committed docs/diagrams — seeded from the current, drift-proof system docs.

**Architecture:** iCloud Drive folder is the only filesystem both iPad and Mac share, so it is the bridge (`Selene-Diagrams/`). Keeper diagrams live git-versioned in `docs/diagrams/` as `<topic>.png` + interpretation `.md` pairs. The seed is rendered to PNG by a puppeteer script from `backend-block-diagrams.md`, which is first brought current against the generated `SYSTEM-MAP.md`. No new daemon — Claude does the copy+commit during a lap.

**Tech Stack:** TypeScript + ts-node, puppeteer (already installed), jest (existing test runner), macOS iCloud Drive, the `diagram-sync` skill.

**Design doc:** [2026-06-08-freeform-diagram-loop-design.md](2026-06-08-freeform-diagram-loop-design.md)

---

## Task 1: Create the bridge folders + repo index

**Files:**
- Create: `~/Library/Mobile Documents/com~apple~CloudDocs/Selene-Diagrams/` (iCloud inbox)
- Create: `docs/diagrams/README.md` (repo home + index)
- Create: `docs/diagrams/.gitkeep` is not needed (README serves)

**Step 1: Create the iCloud inbox folder**

Run:
```bash
mkdir -p ~/Library/Mobile\ Documents/com~apple~CloudDocs/Selene-Diagrams
ls -d ~/Library/Mobile\ Documents/com~apple~CloudDocs/Selene-Diagrams && echo "inbox ready"
```
Expected: prints the path + `inbox ready`. (It will appear in the iPad Files app under iCloud Drive › Selene-Diagrams within a minute.)

**Step 2: Create the repo diagrams home + index**

Create `docs/diagrams/README.md`:
```markdown
# Selene Diagrams

Hand-drawn diagrams of how Selene works / should work, captured in the
**Freeform ⇄ repo visual thinking loop** (see
[design doc](../plans/2026-06-08-freeform-diagram-loop-design.md)).

Each keeper is a pair: `<topic>.png` (the drawing) + `<topic>.md`
(Claude's reading of it + links to any design docs it spawned).

## Index

| Diagram | Captured | What it's about |
|---------|----------|-----------------|
| _(none yet — first lap pending)_ | | |
```

**Step 3: Commit**

```bash
git add docs/diagrams/README.md
git commit -m "feat(diagrams): create docs/diagrams home + index for the Freeform loop"
```

---

## Task 2: Bring the seed source (`backend-block-diagrams.md`) current

The seed must start from truth. `backend-block-diagrams.md` is currently missing
3 real workflows (`folio-feedback`, `generate-worksheet`, `synthesize-topics`).

**Files:**
- Modify: `docs/backend-block-diagrams.md`
- Reference: `docs/SYSTEM-MAP.md` (source of truth)

**Step 1: Confirm SYSTEM-MAP is itself current**

Run: `npx ts-node scripts/gen-system-map.ts --check`
Expected: exit 0 (no drift). If it fails, run `npx ts-node scripts/gen-system-map.ts` and commit the regenerated map first.

**Step 2: Update the block diagrams via the diagram-sync skill**

Invoke the `diagram-sync` skill (it exists for exactly this). Ensure the three
missing workflows are represented in the relevant layer diagrams:
- `folio-feedback` (every 5 min) — processing → Folio feedback files
- `generate-worksheet` (server routes) — iPad worksheet build/apply
- `synthesize-topics` (daily 02:00) — clustering → `topic_clusters`

**Step 3: Verify no workflow is missing**

Run:
```bash
for w in $(ls src/workflows/*.ts | grep -v '\.test\.' | xargs -n1 basename | sed 's/.ts//'); do
  grep -q "$w" docs/backend-block-diagrams.md || echo "STILL MISSING: $w";
done; echo "check done"
```
Expected: only `check done` (no `STILL MISSING` lines).

**Step 4: Commit**

```bash
git add docs/backend-block-diagrams.md
git commit -m "docs: sync backend-block-diagrams with SYSTEM-MAP (add 3 missing workflows)"
```

---

## Task 3: Seed-render script (testable core + puppeteer shell)

Build `scripts/render-seed-diagram.ts`: extract an ASCII section from a markdown
doc, wrap it in styled monospace HTML, screenshot to PNG into the iCloud inbox.
The standing rule (regenerate-before-seed) is enforced by checking SYSTEM-MAP drift first.

**Files:**
- Create: `scripts/render-seed-diagram.ts`
- Create: `src/lib/seed-diagram.ts` (pure core: extract + buildHtml)
- Test: `src/lib/seed-diagram.test.ts`

**Step 1: Write the failing test for the pure core**

Create `src/lib/seed-diagram.test.ts`:
```typescript
import { extractAsciiBlock, buildSeedHtml } from './seed-diagram';

describe('extractAsciiBlock', () => {
  const md = [
    '## 1. System Architecture Overview',
    '',
    '```',
    'BOX A --> BOX B',
    '```',
    '',
    '## 2. Other',
    '```',
    'unrelated',
    '```',
  ].join('\n');

  it('returns the fenced block under the requested heading', () => {
    expect(extractAsciiBlock(md, 'System Architecture Overview')).toBe('BOX A --> BOX B');
  });

  it('throws a clear error when the heading is absent', () => {
    expect(() => extractAsciiBlock(md, 'Nope')).toThrow(/heading not found/i);
  });
});

describe('buildSeedHtml', () => {
  it('embeds the content in a monospace <pre> and escapes HTML', () => {
    const html = buildSeedHtml('a --> b <tag>', 'Title');
    expect(html).toContain('<pre');
    expect(html).toContain('a --&gt; b &lt;tag&gt;');
    expect(html).toContain('Title');
  });
});
```

**Step 2: Run it to verify it fails**

Run: `npx jest src/lib/seed-diagram.test.ts`
Expected: FAIL — module not found / functions undefined.

**Step 3: Implement the pure core**

Create `src/lib/seed-diagram.ts`:
```typescript
/** Extract the first fenced code block following a markdown heading that contains `heading`. */
export function extractAsciiBlock(markdown: string, heading: string): string {
  const lines = markdown.split('\n');
  const headingIdx = lines.findIndex(
    (l) => /^#{1,6}\s/.test(l) && l.toLowerCase().includes(heading.toLowerCase()),
  );
  if (headingIdx === -1) throw new Error(`Seed heading not found: "${heading}"`);
  const start = lines.findIndex((l, i) => i > headingIdx && l.trim().startsWith('```'));
  if (start === -1) throw new Error(`No code block under heading: "${heading}"`);
  const end = lines.findIndex((l, i) => i > start && l.trim().startsWith('```'));
  if (end === -1) throw new Error(`Unterminated code block under heading: "${heading}"`);
  return lines.slice(start + 1, end).join('\n').replace(/\s+$/, '');
}

const escapeHtml = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Wrap ASCII content in a clean, high-contrast monospace page for screenshotting. */
export function buildSeedHtml(content: string, title: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    body { margin: 0; background: #ffffff; color: #111; }
    .wrap { padding: 40px; display: inline-block; }
    h1 { font: 600 28px -apple-system, system-ui, sans-serif; margin: 0 0 24px; }
    pre { font: 16px/1.35 ui-monospace, "SF Mono", Menlo, monospace; white-space: pre; margin: 0; }
  </style></head><body><div class="wrap">
    <h1>${escapeHtml(title)}</h1><pre>${escapeHtml(content)}</pre>
  </div></body></html>`;
}
```

**Step 4: Run the test to verify it passes**

Run: `npx jest src/lib/seed-diagram.test.ts`
Expected: PASS (4 assertions).

**Step 5: Write the puppeteer shell script**

Create `scripts/render-seed-diagram.ts`:
```typescript
import { execSync } from 'child_process';
import { promises as fs } from 'fs';
import * as os from 'os';
import * as path from 'path';
import puppeteer from 'puppeteer';
import { extractAsciiBlock, buildSeedHtml } from '../src/lib/seed-diagram';

const INBOX = path.join(
  os.homedir(),
  'Library/Mobile Documents/com~apple~CloudDocs/Selene-Diagrams',
);
const SOURCE = 'docs/backend-block-diagrams.md';
const HEADING = process.argv[2] || 'System Architecture Overview';

async function main(): Promise<void> {
  // Standing rule: never seed from a stale picture.
  try {
    execSync('npx ts-node scripts/gen-system-map.ts --check', { stdio: 'ignore' });
  } catch {
    console.error('⚠️  SYSTEM-MAP.md is OUT OF DATE. Regenerate it and re-sync ' +
      'backend-block-diagrams.md before seeding (see plan Task 2). Aborting.');
    process.exit(1);
  }

  const md = await fs.readFile(SOURCE, 'utf8');
  const ascii = extractAsciiBlock(md, HEADING);
  const html = buildSeedHtml(ascii, `Selene — ${HEADING}`);

  await fs.mkdir(INBOX, { recursive: true });
  const out = path.join(INBOX, `seed-${HEADING.toLowerCase().replace(/[^a-z0-9]+/g, '-')}.png`);

  const browser = await puppeteer.launch();
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1600, height: 1200, deviceScaleFactor: 2 });
    await page.setContent(html, { waitUntil: 'load' });
    const el = await page.$('.wrap');
    if (!el) throw new Error('render target .wrap not found');
    await el.screenshot({ path: out });
  } finally {
    await browser.close();
  }
  console.log(`Seed written: ${out}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
```

**Step 6: Commit**

```bash
git add src/lib/seed-diagram.ts src/lib/seed-diagram.test.ts scripts/render-seed-diagram.ts
git commit -m "feat(diagrams): seed-render script (tested core + puppeteer png)"
```

---

## Task 4: Run the first seed lap (end-to-end proof)

**Step 1: Render the seed**

Run: `npx ts-node scripts/render-seed-diagram.ts`
Expected: `Seed written: …/Selene-Diagrams/seed-system-architecture-overview.png`

**Step 2: Sanity-check Claude can read it**

Use the `Read` tool on the generated PNG path. Confirm the architecture text is legible.

**Step 3: Hand off to the user**

Tell the user: open Freeform on iPad → new board → insert from Photos/Files →
iCloud Drive › Selene-Diagrams › the seed PNG → draw on top → share-sheet →
Save to Files → Selene-Diagrams.

**Step 4: Close the first lap when a drawing arrives**

When the user reports a new drawing, find the newest export (ignore the `seed-` PNG):
```bash
INBOX=~/Library/Mobile\ Documents/com~apple~CloudDocs/Selene-Diagrams
ls -t "$INBOX"/*.png | grep -v '/seed-' | head -1
```
`Read` that newest PNG to interpret it. Then **capture with overwrite semantics**
(one stable file per topic — git holds the history, the folder stays clean):
```bash
# 1. Overwrite the keeper in place (NO -v2 suffixes — re-drawing a topic replaces it)
cp -f "<newest.png>" docs/diagrams/<topic>.png
# 2. Clear the drawing exports so copies never accumulate (keep the reusable seed)
find "$INBOX" -name '*.png' ! -name 'seed-*' -delete   # safe: the keeper is already in the repo
```
Write/overwrite `docs/diagrams/<topic>.md` (Claude's interpretation + links). In
`docs/diagrams/README.md`, **update the existing row** for this topic if present,
else add one — never duplicate a topic. Commit (git diff shows it as a modify, not
a new copy, on subsequent laps):
```bash
git add docs/diagrams/<topic>.png docs/diagrams/<topic>.md docs/diagrams/README.md
git commit -m "diagrams: capture <topic>"
```

> **Overwrite rule (applies every lap, not just the first):** repo keepers are
> overwritten in place; the iCloud inbox is cleared after capture. Nothing is lost
> — `git log -- docs/diagrams/<topic>.png` recovers any prior version.

---

## Task 5: User guide (wrap-up — mandatory per CLAUDE.md)

**Files:**
- Create: `docs/guides/features/diagram-loop.md` (from `docs/guides/features/_TEMPLATE.md`)
- Modify: `docs/USER-EXPERIENCE.md` (add hub link)

**Step 1:** Copy the template and write the guide, operator-facing first:
Using it (the iPad steps) → How it works (the bridge + seed) → Configure
(inbox path, seed heading arg) → Troubleshooting (PNG not appearing = iCloud
sync lag; stale-seed abort = run Task 2) → Related (design doc, SYSTEM-MAP).

**Step 2:** Add the guide's link to `docs/USER-EXPERIENCE.md`.

**Step 3: Commit**
```bash
git add docs/guides/features/diagram-loop.md docs/USER-EXPERIENCE.md
git commit -m "docs(guides): add diagram-loop feature guide + hub link"
```

**Step 4:** Move the design doc Vision/Ready → Done in `docs/plans/INDEX.md`.

---

## Notes
- DRY: the pure core (`seed-diagram.ts`) is reused by any future renderer; the script is a thin shell.
- YAGNI: no launchd watcher, no Freeform write-back, no OCR — all explicit non-goals.
- The whole plan is doc/script work; the only unit-tested unit is the markdown→HTML core, which is where the real logic lives.
