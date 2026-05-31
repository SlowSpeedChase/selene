# Living System Map Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a drift-proof, zoomable codebase-comprehension system: a generated `docs/SYSTEM-MAP.md` workflow inventory (read from code + plists) sitting between `CLAUDE.md` (pointers) and the deep block diagrams + source.

**Architecture:** Pure parsing/rendering logic lives in `src/lib/system-map.ts` (unit-tested under jest). A thin CLI `scripts/gen-system-map.ts` reads `src/workflows/*.ts` + `launchd/*.plist`, builds the workflow table, and injects it into `docs/SYSTEM-MAP.md` between `<!-- GENERATED -->` markers. A `--check` mode diffs without writing (non-zero on drift) and is wired into the Stop hook. Facts are generated; meaning is hand-written outside the markers.

**Tech Stack:** TypeScript, ts-node, jest + ts-jest (allowlisted `src/lib/*.test.ts`), bash hook.

---

## Conventions established by this plan

**The `// @map` comment** — placed at the top of each workflow file, harvested by the generator:

```ts
// @map purpose: Extract concepts, themes, energy, and essence from pending notes
// @map reads: raw_notes
// @map writes: processed_notes
// @map trigger: launchd (every 5 min)      ← OPTIONAL; only for non-plist workflows or to override
```

- Grammar: `^//\s*@map\s+(purpose|reads|writes|trigger):\s*(.+)$`, one key per line.
- `purpose` may contain commas freely. `reads`/`writes` are comma-separated table lists.
- `trigger` is optional; if absent, the generator derives the schedule from the matching plist, or shows `—` if there is no plist.
- A workflow with NO `// @map` comment still appears in the table (purpose = `—`) so it can never be silently missing.

**Plist → workflow mapping:** workflow `X.ts` maps to `launchd/com.selene.X.plist`. If no such plist exists, schedule = derived from `@map trigger:` or `—`.

---

### Task 1: Schedule parser (pure function)

**Files:**
- Create: `src/lib/system-map.ts`
- Test: `src/lib/system-map.test.ts`
- Modify: `jest.config.js` (add the new test to the `testMatch` allowlist)

**Step 1: Add the test file to the jest allowlist**

In `jest.config.js`, add inside the `testMatch` array:
```js
    '**/src/lib/system-map.test.ts',
```

**Step 2: Write the failing test**

```ts
// src/lib/system-map.test.ts
import { describe, it, expect } from '@jest/globals';
import { parseSchedule } from './system-map';

describe('parseSchedule', () => {
  it('humanizes StartInterval seconds', () => {
    const plist = `<key>StartInterval</key>\n<integer>300</integer>`;
    expect(parseSchedule(plist)).toBe('every 5 min');
  });

  it('humanizes a 30-min interval', () => {
    expect(parseSchedule(`<key>StartInterval</key><integer>1800</integer>`)).toBe('every 30 min');
  });

  it('humanizes an hourly interval', () => {
    expect(parseSchedule(`<key>StartInterval</key><integer>3600</integer>`)).toBe('hourly');
  });

  it('renders StartCalendarInterval as a daily time', () => {
    const plist = `<key>StartCalendarInterval</key><dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>`;
    expect(parseSchedule(plist)).toBe('daily 06:00');
  });

  it('returns null when no schedule key is present', () => {
    expect(parseSchedule(`<key>RunAtLoad</key><true/>`)).toBeNull();
  });
});
```

**Step 3: Run test to verify it fails**

Run: `npx jest src/lib/system-map.test.ts`
Expected: FAIL — `parseSchedule` not exported / module missing.

**Step 4: Implement `parseSchedule` in `src/lib/system-map.ts`**

```ts
/** Parse a launchd plist's schedule into a human label, or null if none. */
export function parseSchedule(plistXml: string): string | null {
  const interval = plistXml.match(/<key>StartInterval<\/key>\s*<integer>(\d+)<\/integer>/);
  if (interval) {
    const secs = parseInt(interval[1], 10);
    if (secs % 3600 === 0) {
      const h = secs / 3600;
      return h === 1 ? 'hourly' : `every ${h} hr`;
    }
    return `every ${Math.round(secs / 60)} min`;
  }
  const cal = plistXml.match(/<key>StartCalendarInterval<\/key>\s*<dict>([\s\S]*?)<\/dict>/);
  if (cal) {
    const hour = cal[1].match(/<key>Hour<\/key>\s*<integer>(\d+)<\/integer>/);
    const min = cal[1].match(/<key>Minute<\/key>\s*<integer>(\d+)<\/integer>/);
    const hh = (hour ? hour[1] : '0').padStart(2, '0');
    const mm = (min ? min[1] : '0').padStart(2, '0');
    return `daily ${hh}:${mm}`;
  }
  return null;
}
```

**Step 5: Run test to verify it passes**

Run: `npx jest src/lib/system-map.test.ts`
Expected: PASS (5 tests).

**Step 6: Commit**

```bash
git add src/lib/system-map.ts src/lib/system-map.test.ts jest.config.js
git commit -m "feat(system-map): plist schedule parser"
```

---

### Task 2: `@map` comment parser (pure function)

**Files:**
- Modify: `src/lib/system-map.ts`
- Test: `src/lib/system-map.test.ts`

**Step 1: Write the failing test** (append to the existing describe block / add a new one)

```ts
import { parseMapComment } from './system-map';

describe('parseMapComment', () => {
  it('extracts purpose, reads, writes, trigger', () => {
    const src = [
      '// @map purpose: Extract concepts, themes, energy',
      '// @map reads: raw_notes',
      '// @map writes: processed_notes',
      '// @map trigger: webhook',
      'import { foo } from "bar";',
    ].join('\n');
    expect(parseMapComment(src)).toEqual({
      purpose: 'Extract concepts, themes, energy',
      reads: 'raw_notes',
      writes: 'processed_notes',
      trigger: 'webhook',
    });
  });

  it('returns empty fields when no @map comment present', () => {
    expect(parseMapComment('import x from "y";')).toEqual({});
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx jest src/lib/system-map.test.ts -t parseMapComment`
Expected: FAIL — not exported.

**Step 3: Implement `parseMapComment`**

```ts
export interface MapMeta {
  purpose?: string;
  reads?: string;
  writes?: string;
  trigger?: string;
}

/** Harvest `// @map <key>: <value>` lines from the top of a workflow file. */
export function parseMapComment(source: string): MapMeta {
  const meta: MapMeta = {};
  const re = /^\/\/\s*@map\s+(purpose|reads|writes|trigger):\s*(.+)$/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source)) !== null) {
    meta[m[1] as keyof MapMeta] = m[2].trim();
  }
  return meta;
}
```

**Step 4: Run test to verify it passes**

Run: `npx jest src/lib/system-map.test.ts -t parseMapComment`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/lib/system-map.ts src/lib/system-map.test.ts
git commit -m "feat(system-map): @map doc-comment parser"
```

---

### Task 3: Table renderer (pure function)

**Files:**
- Modify: `src/lib/system-map.ts`
- Test: `src/lib/system-map.test.ts`

**Step 1: Write the failing test**

```ts
import { renderWorkflowTable, WorkflowRow } from './system-map';

describe('renderWorkflowTable', () => {
  it('renders a sorted markdown table with links', () => {
    const rows: WorkflowRow[] = [
      { name: 'process-llm', schedule: 'every 5 min', purpose: 'Extract concepts', reads: 'raw_notes', writes: 'processed_notes' },
      { name: 'ingest', schedule: 'webhook', purpose: 'Capture notes', reads: '—', writes: 'raw_notes' },
    ];
    const md = renderWorkflowTable(rows);
    // sorted alphabetically: ingest before process-llm
    expect(md.indexOf('ingest')).toBeLessThan(md.indexOf('process-llm'));
    // links to source
    expect(md).toContain('[ingest](../src/workflows/ingest.ts)');
    expect(md).toContain('| Workflow | Schedule | Reads | Writes | Purpose |');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx jest src/lib/system-map.test.ts -t renderWorkflowTable`
Expected: FAIL.

**Step 3: Implement `renderWorkflowTable` + `WorkflowRow`**

```ts
export interface WorkflowRow {
  name: string;
  schedule: string;
  purpose: string;
  reads: string;
  writes: string;
}

export function renderWorkflowTable(rows: WorkflowRow[]): string {
  const sorted = [...rows].sort((a, b) => a.name.localeCompare(b.name));
  const header = '| Workflow | Schedule | Reads | Writes | Purpose |\n|---|---|---|---|---|';
  const body = sorted
    .map(
      (r) =>
        `| [${r.name}](../src/workflows/${r.name}.ts) | ${r.schedule} | ${r.reads} | ${r.writes} | ${r.purpose} |`
    )
    .join('\n');
  return `${header}\n${body}`;
}
```

**Step 4: Run test to verify it passes**

Run: `npx jest src/lib/system-map.test.ts -t renderWorkflowTable`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/lib/system-map.ts src/lib/system-map.test.ts
git commit -m "feat(system-map): workflow table renderer"
```

---

### Task 4: Marker injection (pure function)

**Files:**
- Modify: `src/lib/system-map.ts`
- Test: `src/lib/system-map.test.ts`

**Step 1: Write the failing test**

```ts
import { injectGenerated } from './system-map';

describe('injectGenerated', () => {
  const START = '<!-- GENERATED:workflows START -->';
  const END = '<!-- GENERATED:workflows END -->';

  it('replaces content between markers, preserving prose outside', () => {
    const doc = `# Map\n\nHand-written intro.\n\n${START}\nOLD TABLE\n${END}\n\nHand-written outro.`;
    const out = injectGenerated(doc, 'NEW TABLE');
    expect(out).toContain('Hand-written intro.');
    expect(out).toContain('Hand-written outro.');
    expect(out).toContain('NEW TABLE');
    expect(out).not.toContain('OLD TABLE');
  });

  it('throws if markers are missing', () => {
    expect(() => injectGenerated('no markers here', 'X')).toThrow();
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx jest src/lib/system-map.test.ts -t injectGenerated`
Expected: FAIL.

**Step 3: Implement `injectGenerated`**

```ts
const MARK_START = '<!-- GENERATED:workflows START -->';
const MARK_END = '<!-- GENERATED:workflows END -->';

export function injectGenerated(doc: string, generated: string): string {
  const start = doc.indexOf(MARK_START);
  const end = doc.indexOf(MARK_END);
  if (start === -1 || end === -1 || end < start) {
    throw new Error('SYSTEM-MAP.md is missing the GENERATED:workflows markers');
  }
  const before = doc.slice(0, start + MARK_START.length);
  const after = doc.slice(end);
  return `${before}\n${generated}\n${after}`;
}
```

**Step 4: Run test to verify it passes**

Run: `npx jest src/lib/system-map.test.ts -t injectGenerated`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/lib/system-map.ts src/lib/system-map.test.ts
git commit -m "feat(system-map): marker injection (preserves hand-written prose)"
```

---

### Task 5: The CLI generator (`scripts/gen-system-map.ts`)

This is the thin, untested shell that reads the filesystem and orchestrates the pure functions. It also adds `buildRows` to the lib (testable) but the file-walking shell itself is verified by running it.

**Files:**
- Modify: `src/lib/system-map.ts` (add `buildRow` helper — pure, tested)
- Create: `scripts/gen-system-map.ts`
- Test: `src/lib/system-map.test.ts`

**Step 1: Write the failing test for `buildRow`**

```ts
import { buildRow } from './system-map';

describe('buildRow', () => {
  it('prefers plist schedule, falls back to @map trigger, then dash', () => {
    const meta = { purpose: 'P', reads: 'a', writes: 'b' };
    expect(buildRow('export-obsidian', meta, 'hourly').schedule).toBe('hourly');
    expect(buildRow('ingest', { ...meta, trigger: 'webhook' }, null).schedule).toBe('webhook');
    expect(buildRow('mystery', {}, null)).toEqual({
      name: 'mystery', schedule: '—', purpose: '—', reads: '—', writes: '—',
    });
  });
});
```

**Step 2: Run to verify fail**

Run: `npx jest src/lib/system-map.test.ts -t buildRow` → FAIL.

**Step 3: Implement `buildRow`**

```ts
export function buildRow(name: string, meta: MapMeta, plistSchedule: string | null): WorkflowRow {
  return {
    name,
    schedule: plistSchedule ?? meta.trigger ?? '—',
    purpose: meta.purpose ?? '—',
    reads: meta.reads ?? '—',
    writes: meta.writes ?? '—',
  };
}
```

**Step 4: Run to verify pass**

Run: `npx jest src/lib/system-map.test.ts -t buildRow` → PASS.

**Step 5: Write the CLI shell**

```ts
// scripts/gen-system-map.ts
// Generates the workflow inventory table in docs/SYSTEM-MAP.md from source.
// Usage:  ts-node scripts/gen-system-map.ts            (write)
//         ts-node scripts/gen-system-map.ts --check    (exit 1 if out of date)
import * as fs from 'fs';
import * as path from 'path';
import {
  parseSchedule,
  parseMapComment,
  buildRow,
  renderWorkflowTable,
  injectGenerated,
  WorkflowRow,
} from '../src/lib/system-map';

const ROOT = path.resolve(__dirname, '..');
const WORKFLOWS_DIR = path.join(ROOT, 'src/workflows');
const LAUNCHD_DIR = path.join(ROOT, 'launchd');
const MAP_DOC = path.join(ROOT, 'docs/SYSTEM-MAP.md');

function buildRows(): WorkflowRow[] {
  const files = fs
    .readdirSync(WORKFLOWS_DIR)
    .filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'));
  return files.map((f) => {
    const name = f.replace(/\.ts$/, '');
    const src = fs.readFileSync(path.join(WORKFLOWS_DIR, f), 'utf8');
    const meta = parseMapComment(src);
    const plistPath = path.join(LAUNCHD_DIR, `com.selene.${name}.plist`);
    const plistSchedule = fs.existsSync(plistPath)
      ? parseSchedule(fs.readFileSync(plistPath, 'utf8'))
      : null;
    return buildRow(name, meta, plistSchedule);
  });
}

function main(): void {
  const check = process.argv.includes('--check');
  const table = renderWorkflowTable(buildRows());
  const current = fs.readFileSync(MAP_DOC, 'utf8');
  const next = injectGenerated(current, table);

  if (check) {
    if (next !== current) {
      console.error('SYSTEM-MAP.md is OUT OF DATE. Run: npx ts-node scripts/gen-system-map.ts');
      process.exit(1);
    }
    console.log('SYSTEM-MAP.md is current.');
    return;
  }
  fs.writeFileSync(MAP_DOC, next);
  console.log(`SYSTEM-MAP.md updated (${buildRows().length} workflows).`);
}

main();
```

**Step 6: Commit (generator code only — doc doesn't exist yet, so don't run it)**

```bash
git add src/lib/system-map.ts src/lib/system-map.test.ts scripts/gen-system-map.ts
git commit -m "feat(system-map): generator CLI (write + --check)"
```

---

### Task 6: Create `docs/SYSTEM-MAP.md` and generate the real table (THE FIRST WIN)

**Files:**
- Create: `docs/SYSTEM-MAP.md`

**Step 1: Write the hand-authored skeleton** (the L1 narrative + empty markers)

```markdown
# Selene System Map

> **The live, zoomable index of Selene.** The workflow table below is
> **generated** from `src/workflows/*.ts` + `launchd/*.plist` — do not hand-edit
> between the markers. Everything outside the markers is hand-written meaning.
>
> Zoom: **[CLAUDE.md](../CLAUDE.md)** (what & where) → **this file** (the inventory)
> → **[block diagrams](backend-block-diagrams.md)** + the workflow source (deep detail).

## How Selene flows

Capture (Drafts/eink/voice → `raw_notes`) → Process (LLM extraction, essences,
synthesis) → Browse/Deliver (Obsidian vault, Apple Notes digest, worksheets, Folio).
See the [block diagrams](backend-block-diagrams.md) for the full picture.

## Workflows (generated)

<!-- GENERATED:workflows START -->
<!-- GENERATED:workflows END -->

## Regenerating

```bash
npx ts-node scripts/gen-system-map.ts          # rewrite the table
npx ts-node scripts/gen-system-map.ts --check  # CI/hook drift check
```
```

**Step 2: Add `@map` comments to all workflows**

For each of the 12 workflows in `src/workflows/`, read the file's actual behavior and add a `// @map` block at the top. Verify reads/writes against real SQL in each file — do not guess. Workflows: agent-manager, daily-summary, distill-essences, eink-ingest, export-obsidian, folio-feedback, generate-worksheet, ingest, process-llm, send-digest, synthesize-topics, voice-ingest.

For non-plist workflows (`ingest`, `generate-worksheet`), include a `// @map trigger:` line (e.g. `webhook /webhook/api/drafts`, `on-demand (server route)`).

Commit the comments:
```bash
git add src/workflows/*.ts
git commit -m "docs(system-map): add @map doc-comments to all workflows"
```

**Step 3: Generate the table**

Run: `npx ts-node scripts/gen-system-map.ts`
Expected output: `SYSTEM-MAP.md updated (12 workflows).`

**Step 4: Verify the win**

Run: `grep -c '../src/workflows/' docs/SYSTEM-MAP.md`
Expected: 12 — proving all 12 workflows are present (vs the 6 CLAUDE.md claimed).

**Step 5: Verify --check is green**

Run: `npx ts-node scripts/gen-system-map.ts --check`
Expected: `SYSTEM-MAP.md is current.` (exit 0)

**Step 6: Commit**

```bash
git add docs/SYSTEM-MAP.md
git commit -m "docs(system-map): generate live 12-workflow inventory"
```

---

### Task 7: Wire the Stop-hook drift guard

**Files:**
- Modify: `.claude/hooks/session-end-reminders.sh`

**Step 1: Edit the hook**

When workflow/launchd files changed, run `--check` and append its result to the reminder. Replace the `if [ -n "$changed" ]` branch so it runs the check:

```bash
if [ -n "$changed" ]; then
  drift=""
  if ! npx ts-node scripts/gen-system-map.ts --check >/dev/null 2>&1; then
    drift=" SYSTEM-MAP.md is OUT OF DATE — run: npx ts-node scripts/gen-system-map.ts."
  fi
  echo "{\"systemMessage\": \"Session end: Workflow or launchd files changed.${drift} Also update docs/backend-block-diagrams.md and docs/USER-EXPERIENCE.md if needed.\"}"
else
  echo '{"systemMessage": "Session end: Update docs/USER-EXPERIENCE.md if any workflows, features, or status changed this session."}'
fi
```

**Step 2: Test the guard fires on drift**

Temporarily edit a workflow's `@map purpose:` line, then run the hook body manually:
```bash
git stash list >/dev/null; bash .claude/hooks/session-end-reminders.sh
```
Expected: the message contains "SYSTEM-MAP.md is OUT OF DATE". Then regenerate (`npx ts-node scripts/gen-system-map.ts`) and re-run — message should no longer contain it. Revert the temporary edit.

**Step 3: Commit**

```bash
git add .claude/hooks/session-end-reminders.sh
git commit -m "feat(system-map): Stop-hook drift guard via gen-system-map --check"
```

---

### Task 8: Retire the stale facts in CLAUDE.md + block diagrams

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/backend-block-diagrams.md`

**Step 1: CLAUDE.md** — replace hard-coded counts with a pointer. Find occurrences of "6 active" / "6 workflows" / "6 launchd agents" and the `src/workflows/` tree comment; change to language like "the workflows (see **[docs/SYSTEM-MAP.md](docs/SYSTEM-MAP.md)** for the live inventory)". Do NOT restate a count.

**Step 2: backend-block-diagrams.md** — add under the title:
```markdown
> **Inventory of record:** [docs/SYSTEM-MAP.md](SYSTEM-MAP.md) (generated). This file is the *deep* view; if the two disagree on which workflows exist, SYSTEM-MAP.md wins.
```

**Step 3: Verify no stale count remains**

Run: `grep -nE '6 (active )?(workflows|launchd)' CLAUDE.md` → expect no matches.

**Step 4: Commit**

```bash
git add CLAUDE.md docs/backend-block-diagrams.md
git commit -m "docs: point CLAUDE.md + block diagrams at generated SYSTEM-MAP.md"
```

---

### Task 9: User guide + wrap-up (MANDATORY per CLAUDE.md)

**Files:**
- Create: `docs/guides/features/system-map.md` (from `docs/guides/features/_TEMPLATE.md`)
- Modify: `docs/USER-EXPERIENCE.md` (add hub link)
- Modify: `docs/plans/INDEX.md` (move design Ready → Done)

**Step 1:** Write `system-map.md` — structure: Using it (open SYSTEM-MAP.md to see the whole system) → How it works (generated from code + plists, markers, zoom ladder) → Configure & customize (the `@map` comment grammar) → Troubleshooting (drift guard, regenerate command) → Related (block diagrams, CLAUDE.md). Verify every claim against the real script.

**Step 2:** Add a link to the new guide in `docs/USER-EXPERIENCE.md`.

**Step 3:** In `docs/plans/INDEX.md`, move the design-doc row from **Ready** to **Done** (user-facing = yes; guide created).

**Step 4: Final verification**

Run: `npx jest src/lib/system-map.test.ts && npx ts-node scripts/gen-system-map.ts --check`
Expected: all unit tests PASS, check reports current.

**Step 5: Commit**

```bash
git add docs/guides/features/system-map.md docs/USER-EXPERIENCE.md docs/plans/INDEX.md
git commit -m "docs(system-map): user guide + mark design Done"
```

---

## Done when

- `docs/SYSTEM-MAP.md` lists all 12 workflows, generated, between markers.
- `gen-system-map --check` gates drift and is wired into the Stop hook.
- `CLAUDE.md` points to the map instead of stating a stale count.
- A user guide exists and is linked from the hub.
- All `src/lib/system-map.test.ts` tests pass.
