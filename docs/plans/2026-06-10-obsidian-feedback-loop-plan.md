# Obsidian Feedback Loop ("Your note") — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A `## ✍️ Your note` section in every exported Obsidian note where the user types free-text intent; a new `vault-feedback` workflow ingests it into a precious `facts.db` table, re-pends the note so `process-llm` re-derives its filing with the intent in-prompt, and the exporter renders the feedback back as an applied-✓ block.

**Architecture:** Pure/DI-tested logic lives in `src/lib/vault-feedback.ts` (parser, scanner, intent helpers), mirroring `obsidian-render.ts` (which gains the section render + preserve-on-render). `src/workflows/vault-feedback.ts` is a thin singleton-wired wrapper, scheduled by a canonical `launchd/com.selene.vault-feedback.plist` (prod plist generated from it by `install-prod.sh`). Re-filing = `setNoteState(status:'pending')`; durability = the table lives in `facts.db` keyed on `captured_notes.id`.

**Tech Stack:** TypeScript, better-sqlite3 (two-file ATTACH), jest, launchd. Design doc: `docs/plans/2026-06-10-obsidian-feedback-loop-design.md` (read it first — especially the three plan-time corrections in §2/§3).

**Conventions you must follow (this codebase):**
- NO `any` types. Parameterized SQL only.
- lib modules take an explicit `db: DB` param (NO importing the `db` singleton into lib code) — that's what makes them jest-testable via `makeTwoFileTestDb()` (`src/lib/test-two-file-db.ts`).
- `facts.` is the ATTACH alias: writes to the precious store are `INSERT INTO facts.note_feedback ...`; the `raw_notes` VIEW is read-only.
- Run all commands from the worktree root. `npx jest <file>` for one suite, `npm test` for all, `npx tsc --noEmit` for the type gate. The pre-push hook runs tsc + jest + `gen-system-map --check`.

---

### Task 0: Worktree + branch

**Step 1: Create the worktree (from the main checkout, `/Users/chaseeasterling/selene`)**

```bash
git fetch origin && git rev-list --left-right --count origin/main...main
```
Expected: `0 N` or `0 0` (local main not behind; local may be ahead — that's fine, branch from LOCAL main). If behind, stop and reconcile first.

```bash
git worktree add -b feat/obsidian-feedback-loop .worktrees/obsidian-feedback-loop main
cp templates/BRANCH-STATUS.md .worktrees/obsidian-feedback-loop/BRANCH-STATUS.md
cd .worktrees/obsidian-feedback-loop
```

**Step 2: Fill in BRANCH-STATUS.md** (branch name, design doc link, stage = dev) and commit:

```bash
git add BRANCH-STATUS.md && git commit -m "chore: start feat/obsidian-feedback-loop (BRANCH-STATUS)"
```

---

### Task 1: `note_feedback` schema in facts.db

**Files:**
- Modify: `src/lib/facts-db.ts` (add table to `initFactsSchema`)
- Test: `src/lib/facts-db.test.ts` (append to the existing suite)

**Step 1: Write the failing test** — append to `src/lib/facts-db.test.ts` (match the file's existing style; it tests `initFactsSchema` against an in-memory Database):

```typescript
describe('note_feedback (obsidian feedback loop)', () => {
  it('initFactsSchema creates note_feedback with the expected columns', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    const cols = (db.prepare(`PRAGMA table_info(note_feedback)`).all() as Array<{ name: string }>)
      .map((c) => c.name);
    expect(cols).toEqual(['id', 'raw_note_id', 'feedback_text', 'original_filing', 'created_at', 'applied_at']);
    db.close();
  });

  it('is idempotent (second init does not throw or drop rows)', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    db.prepare(`INSERT INTO note_feedback (raw_note_id, feedback_text, created_at) VALUES (1, 'x', '2026-06-10')`).run();
    initFactsSchema(db);
    expect(db.prepare(`SELECT COUNT(*) AS n FROM note_feedback`).get()).toEqual({ n: 1 });
    db.close();
  });
});
```

**Step 2: Run it — expect FAIL** (`no such table: note_feedback`):

```bash
npx jest src/lib/facts-db.test.ts
```

**Step 3: Implement** — in `src/lib/facts-db.ts`, inside the `initFactsSchema` template literal, after the `review_state` CREATE TABLE block, add:

```sql
    -- Obsidian feedback loop (2026-06-10 design): free-text author intent captured from the
    -- vault's "Your note" sections. PRECIOUS — human words; survives rebuild by living here.
    -- raw_note_id = captured_notes.id (facts.db is never rebuilt, so the id is stable).
    CREATE TABLE IF NOT EXISTS note_feedback (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      raw_note_id     INTEGER NOT NULL,
      feedback_text   TEXT NOT NULL,
      original_filing TEXT,
      created_at      DATETIME NOT NULL,
      applied_at      DATETIME
    );
    CREATE INDEX IF NOT EXISTS idx_note_feedback_note ON note_feedback(raw_note_id);
```

(No FK across files — SQLite can't FK into an attached db; app-level integrity like `processed_notes.raw_note_id`. `ensureFactsDbInitialized` runs this on every connection open, so prod gets the table on first post-deploy start — no migration script.)

**Step 4: Run tests — expect PASS**, then the full facts-db suite stays green:

```bash
npx jest src/lib/facts-db.test.ts
```

**Step 5: Commit**

```bash
git add src/lib/facts-db.ts src/lib/facts-db.test.ts
git commit -m "feat(feedback): note_feedback table in facts.db (precious author-intent store)"
```

---

### Task 2: Section parser + `selene_id` extractor (pure)

**Files:**
- Create: `src/lib/vault-feedback.ts`
- Create: `src/lib/vault-feedback.test.ts`

**Step 1: Write the failing tests** — `src/lib/vault-feedback.test.ts`:

```typescript
import { parseYourNoteSection, extractSeleneId, YOUR_NOTE_HEADING } from './vault-feedback';

describe('parseYourNoteSection', () => {
  it('returns hasSection=false when the heading is absent', () => {
    expect(parseYourNoteSection('# Title\n\nbody')).toEqual({ hasSection: false, newFeedback: null });
  });

  it('empty section -> no feedback', () => {
    const md = `# T\n\n${YOUR_NOTE_HEADING}\n`;
    expect(parseYourNoteSection(md)).toEqual({ hasSection: true, newFeedback: null });
  });

  it('plain text in the section is new feedback (trimmed, multi-line preserved)', () => {
    const md = `# T\n\n${YOUR_NOTE_HEADING}\n\nThis is a skill I enjoy.\nRemember it.\n`;
    expect(parseYourNoteSection(md).newFeedback).toBe('This is a skill I enjoy.\nRemember it.');
  });

  it('blockquote lines (applied history) are NOT feedback', () => {
    const md = `${YOUR_NOTE_HEADING}\n\n> old feedback\n> — applied 2026-06-10 ✓\n`;
    expect(parseYourNoteSection(md).newFeedback).toBeNull();
  });

  it('mixed: plain text below an applied block is new feedback', () => {
    const md = `${YOUR_NOTE_HEADING}\n\n> old\n> — applied 2026-06-10 ✓\n\nnewer thought\n`;
    expect(parseYourNoteSection(md).newFeedback).toBe('newer thought');
  });

  it('whitespace-only section -> no feedback', () => {
    const md = `${YOUR_NOTE_HEADING}\n   \n\t\n`;
    expect(parseYourNoteSection(md).newFeedback).toBeNull();
  });

  it('stops at the next ## heading (section is bounded)', () => {
    const md = `${YOUR_NOTE_HEADING}\nfeedback here\n## Other\nnot feedback`;
    expect(parseYourNoteSection(md).newFeedback).toBe('feedback here');
  });
});

describe('extractSeleneId', () => {
  it('reads selene_id from frontmatter', () => {
    expect(extractSeleneId('---\ntitle: "x"\nselene_id: 42\ndate: 2026-06-10\n---\n')).toBe(42);
  });
  it('returns null when absent', () => {
    expect(extractSeleneId('---\ntitle: "x"\n---\n')).toBeNull();
  });
});
```

**Step 2: Run — expect FAIL** (module not found):

```bash
npx jest src/lib/vault-feedback.test.ts
```

**Step 3: Implement** — create `src/lib/vault-feedback.ts`:

```typescript
/**
 * Obsidian feedback loop ("Your note") — pure parsing + DI'd scan/ingest helpers.
 *
 * The vault's exported notes end with a `## ✍️ Your note` section. The PROTOCOL (mirrors
 * obsidian-render.ts, which renders the other side): blockquoted lines in the section are
 * Selene's applied-feedback history; any other non-whitespace text is NEW author feedback.
 * Feedback is precious (human words) → facts.note_feedback, keyed on captured_notes.id
 * (total + stable: facts.db is never rebuilt). Design:
 * docs/plans/2026-06-10-obsidian-feedback-loop-design.md
 *
 * Takes an explicit `db` (no module singleton) so it is unit-testable via makeTwoFileTestDb,
 * matching obsidian-render.ts / note-state.ts.
 */
import type { Database as DB } from 'better-sqlite3';
import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';
import { setNoteState } from './note-state';

export const YOUR_NOTE_HEADING = '## ✍️ Your note';

export interface ParsedSection {
  hasSection: boolean;
  newFeedback: string | null;
}

/** Apply the section protocol to a note file's markdown. */
export function parseYourNoteSection(markdown: string): ParsedSection {
  const lines = markdown.split('\n');
  const start = lines.findIndex((l) => l.trim() === YOUR_NOTE_HEADING);
  if (start === -1) return { hasSection: false, newFeedback: null };

  const section: string[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('## ')) break;
    section.push(lines[i]);
  }
  const fresh = section
    .filter((l) => !l.trimStart().startsWith('>'))
    .join('\n')
    .trim();
  return { hasSection: true, newFeedback: fresh.length > 0 ? fresh : null };
}

/** The note's captured_notes.id from the `selene_id:` frontmatter line. */
export function extractSeleneId(markdown: string): number | null {
  const m = markdown.match(/^selene_id: (\d+)$/m);
  return m ? parseInt(m[1], 10) : null;
}
```

**Step 4: Run — expect PASS:**

```bash
npx jest src/lib/vault-feedback.test.ts
```

**Step 5: Commit**

```bash
git add src/lib/vault-feedback.ts src/lib/vault-feedback.test.ts
git commit -m "feat(feedback): Your-note section parser + selene_id extractor"
```

---

### Task 3: Scan + ingest (DB-backed)

**Files:**
- Modify: `src/lib/vault-feedback.ts`
- Create: `src/lib/vault-feedback.db.test.ts`

**Step 1: Write the failing tests** — `src/lib/vault-feedback.db.test.ts`. Use `makeTwoFileTestDb` + a temp vault dir:

```typescript
import { mkdtempSync, writeFileSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import type { Database as DB } from 'better-sqlite3';
import { makeTwoFileTestDb } from './test-two-file-db';
import { scanVaultFeedback, getIntentTexts, markFeedbackApplied, YOUR_NOTE_HEADING } from './vault-feedback';

function seedNote(db: DB, id: number, title: string): void {
  db.prepare(
    `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at)
     VALUES (?, ?, 'content', ?, '2026-06-01T00:00:00.000Z')`
  ).run(id, title, `hash-${id}`);
  db.prepare(
    `CREATE TABLE IF NOT EXISTS processed_notes (
       raw_note_id INTEGER PRIMARY KEY, concepts TEXT, primary_theme TEXT,
       category TEXT, cross_ref_categories TEXT, sub_categories TEXT, essence TEXT)`
  ).run();
}

function noteFile(id: number, sectionBody: string): string {
  return [`---`, `title: "t"`, `selene_id: ${id}`, `---`, ``, `# t`, ``, YOUR_NOTE_HEADING, ``, sectionBody, ``].join('\n');
}

describe('scanVaultFeedback', () => {
  let db: DB;
  let dbDir: string;
  let vaultDir: string;

  beforeEach(() => {
    const t = makeTwoFileTestDb();
    db = t.db;
    dbDir = t.dir;
    vaultDir = mkdtempSync(join(tmpdir(), 'selene-vault-'));
  });

  afterEach(() => {
    db.close();
    rmSync(dbDir, { recursive: true, force: true });
    rmSync(vaultDir, { recursive: true, force: true });
  });

  it('ingests new feedback, snapshots the filing, and re-pends the note', () => {
    seedNote(db, 7, 'a note');
    db.prepare(`INSERT INTO processed_notes (raw_note_id, category, primary_theme) VALUES (7, 'Career & Work', 'old theme')`).run();
    db.prepare(`INSERT INTO note_state (raw_note_id, status, status_folio) VALUES (7, 'processed', 'sent')`).run();
    writeFileSync(join(vaultDir, 'n7.md'), noteFile(7, 'this is a skill I enjoy'));

    const r = scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    expect(r).toMatchObject({ scanned: 1, ingested: 1, duplicates: 0, unmatched: 0, errors: 0 });

    const row = db.prepare(`SELECT * FROM facts.note_feedback WHERE raw_note_id = 7`).get() as {
      feedback_text: string; original_filing: string; applied_at: string | null;
    };
    expect(row.feedback_text).toBe('this is a skill I enjoy');
    expect(JSON.parse(row.original_filing)).toMatchObject({ category: 'Career & Work', primary_theme: 'old theme' });
    expect(row.applied_at).toBeNull();

    // re-pended via the raw_notes view, and unrelated bookkeeping preserved
    const note = db.prepare(`SELECT status FROM raw_notes WHERE id = 7`).get() as { status: string };
    expect(note.status).toBe('pending');
    const state = db.prepare(`SELECT status_folio FROM note_state WHERE raw_note_id = 7`).get() as { status_folio: string };
    expect(state.status_folio).toBe('sent');
  });

  it('is idempotent: a second scan of the same text ingests nothing', () => {
    seedNote(db, 7, 'a note');
    writeFileSync(join(vaultDir, 'n7.md'), noteFile(7, 'same text'));
    scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    const r2 = scanVaultFeedback(db, vaultDir, '2026-06-10T12:05:00.000Z');
    expect(r2).toMatchObject({ ingested: 0, duplicates: 1 });
    expect(db.prepare(`SELECT COUNT(*) AS n FROM facts.note_feedback`).get()).toEqual({ n: 1 });
  });

  it('skips files with no selene_id or an unknown id (unmatched, untouched)', () => {
    writeFileSync(join(vaultDir, 'alien.md'), `# hand-made\n${YOUR_NOTE_HEADING}\nsome text\n`);
    writeFileSync(join(vaultDir, 'ghost.md'), noteFile(999, 'text'));
    const r = scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    expect(r).toMatchObject({ ingested: 0, unmatched: 2 });
  });

  it('unprocessed note (no processed_notes row) snapshots original_filing as NULL', () => {
    seedNote(db, 8, 'fresh');
    writeFileSync(join(vaultDir, 'n8.md'), noteFile(8, 'early feedback'));
    scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    const row = db.prepare(`SELECT original_filing FROM facts.note_feedback WHERE raw_note_id = 8`).get() as { original_filing: string | null };
    expect(row.original_filing).toBeNull();
  });

  it('missing vault dir -> zero result, no throw', () => {
    expect(scanVaultFeedback(db, join(vaultDir, 'nope'), '2026-06-10T12:00:00.000Z'))
      .toMatchObject({ scanned: 0, ingested: 0, errors: 0 });
  });
});

describe('intent helpers', () => {
  it('getIntentTexts returns ALL feedback oldest-first; markFeedbackApplied stamps only un-applied rows', () => {
    const t = makeTwoFileTestDb();
    const ins = t.db.prepare(`INSERT INTO facts.note_feedback (raw_note_id, feedback_text, created_at, applied_at) VALUES (?, ?, ?, ?)`);
    ins.run(7, 'first', '2026-06-01', '2026-06-02');
    ins.run(7, 'second', '2026-06-09', null);
    ins.run(8, 'other note', '2026-06-09', null);

    expect(getIntentTexts(t.db, 7)).toEqual(['first', 'second']);

    markFeedbackApplied(t.db, 7, '2026-06-10T12:00:00.000Z');
    const rows = t.db.prepare(`SELECT feedback_text, applied_at FROM facts.note_feedback ORDER BY id`).all() as Array<{ feedback_text: string; applied_at: string | null }>;
    expect(rows[0].applied_at).toBe('2026-06-02');               // untouched
    expect(rows[1].applied_at).toBe('2026-06-10T12:00:00.000Z'); // stamped
    expect(rows[2].applied_at).toBeNull();                       // other note untouched
    t.db.close();
    rmSync(t.dir, { recursive: true, force: true });
  });
});
```

> NOTE: `makeTwoFileTestDb` does not create `processed_notes`/`note_feedback`-adjacent derived tables — `seedNote` creates the minimal `processed_notes` the snapshot query needs. `note_feedback` itself comes from `initFactsSchema` (Task 1) via `ensureFactsDbInitialized` inside the helper.

**Step 2: Run — expect FAIL** (`scanVaultFeedback` not exported):

```bash
npx jest src/lib/vault-feedback.db.test.ts
```

**Step 3: Implement** — append to `src/lib/vault-feedback.ts`:

```typescript
export interface ScanResult {
  scanned: number;     // files inspected
  ingested: number;    // new feedback rows written (note re-pended)
  duplicates: number;  // identical (note, text) already ingested — awaiting re-export
  unmatched: number;   // no selene_id / id not in captured_notes — skipped, file untouched
  errors: number;      // per-file read/parse exceptions
}

/**
 * Scan every Notes/*.md for new "Your note" text and ingest it. Full scan each run, no
 * watermark: ~300 small files is trivially cheap and the (raw_note_id, feedback_text) dedupe
 * makes rescans idempotent. Never writes to any vault file.
 */
export function scanVaultFeedback(db: DB, notesDir: string, now: string): ScanResult {
  const result: ScanResult = { scanned: 0, ingested: 0, duplicates: 0, unmatched: 0, errors: 0 };

  let files: string[];
  try {
    files = readdirSync(notesDir).filter((f) => f.endsWith('.md'));
  } catch {
    return result; // vault dir missing (fresh dev sandbox) — nothing to scan
  }

  for (const file of files) {
    result.scanned++;
    try {
      const markdown = readFileSync(join(notesDir, file), 'utf-8');
      const { newFeedback } = parseYourNoteSection(markdown);
      if (!newFeedback) continue;

      const noteId = extractSeleneId(markdown);
      const known = noteId !== null
        && db.prepare(`SELECT 1 FROM facts.captured_notes WHERE id = ?`).get(noteId);
      if (!known || noteId === null) {
        result.unmatched++;
        continue;
      }

      const dup = db
        .prepare(`SELECT 1 FROM facts.note_feedback WHERE raw_note_id = ? AND feedback_text = ?`)
        .get(noteId, newFeedback);
      if (dup) {
        result.duplicates++;
        continue;
      }

      // Snapshot the filing being corrected BEFORE re-derivation replaces it (Phase 2's
      // few-shot raw material). NULL when the note was never processed.
      const filing = db
        .prepare(
          `SELECT category, cross_ref_categories, sub_categories, primary_theme, concepts, essence
           FROM processed_notes WHERE raw_note_id = ?`
        )
        .get(noteId) as Record<string, unknown> | undefined;

      db.prepare(
        `INSERT INTO facts.note_feedback (raw_note_id, feedback_text, original_filing, created_at)
         VALUES (?, ?, ?, ?)`
      ).run(noteId, newFeedback, filing ? JSON.stringify(filing) : null, now);

      // Re-pend: derivation-absence machinery does the rest (process-llm INSERT OR REPLACEs).
      // Partial UPSERT preserves unrelated bookkeeping (status_folio, inbox_status, export hash).
      setNoteState(db, noteId, { status: 'pending', processed_at: null });
      result.ingested++;
    } catch {
      result.errors++;
    }
  }
  return result;
}

/** ALL of a note's feedback texts, oldest first — every (re-)derivation carries full intent history. */
export function getIntentTexts(db: DB, rawNoteId: number): string[] {
  const rows = db
    .prepare(
      `SELECT feedback_text FROM facts.note_feedback
       WHERE raw_note_id = ? ORDER BY created_at ASC, id ASC`
    )
    .all(rawNoteId) as Array<{ feedback_text: string }>;
  return rows.map((r) => r.feedback_text);
}

/** Stamp this note's un-applied feedback as applied (called after a successful re-derivation). */
export function markFeedbackApplied(db: DB, rawNoteId: number, now: string): void {
  db.prepare(
    `UPDATE facts.note_feedback SET applied_at = ? WHERE raw_note_id = ? AND applied_at IS NULL`
  ).run(now, rawNoteId);
}
```

**Step 4: Run — expect PASS** (both vault-feedback suites):

```bash
npx jest src/lib/vault-feedback
```

**Step 5: Commit**

```bash
git add src/lib/vault-feedback.ts src/lib/vault-feedback.db.test.ts
git commit -m "feat(feedback): vault scan->ingest->re-pend + intent helpers (DI'd, jest-covered)"
```

---

### Task 4: Prompt injection (pure)

**Files:**
- Modify: `src/lib/prompts.ts`
- Test: `src/lib/prompts.test.ts` (create — there is no prompts test file today)

**Step 1: Write the failing tests** — `src/lib/prompts.test.ts`:

```typescript
import { EXTRACT_PROMPT, buildIntentBlock, buildEssencePrompt } from './prompts';

describe('buildIntentBlock', () => {
  it('empty -> empty string (EXTRACT_PROMPT {intent} replace is a no-op)', () => {
    expect(buildIntentBlock([])).toBe('');
  });

  it('renders each intent as a quoted bullet + the weighting instruction', () => {
    const block = buildIntentBlock(['a skill I enjoy', 'remember  for\nlater']);
    expect(block).toContain('- "a skill I enjoy"');
    expect(block).toContain('- "remember for later"'); // whitespace flattened
    expect(block).toContain('stated intent over the surface topic');
  });
});

describe('EXTRACT_PROMPT {intent} placeholder', () => {
  it('exists exactly once, after the content line', () => {
    expect(EXTRACT_PROMPT.split('{intent}')).toHaveLength(2);
    expect(EXTRACT_PROMPT.indexOf('{content}')).toBeLessThan(EXTRACT_PROMPT.indexOf('{intent}'));
  });
});

describe('buildEssencePrompt with intents', () => {
  it('includes author intent in the context block', () => {
    const p = buildEssencePrompt('t', 'c', null, null, ['a skill I enjoy']);
    expect(p).toContain('The author says this note means: "a skill I enjoy"');
  });
  it('backward compatible without intents', () => {
    expect(buildEssencePrompt('t', 'c', null, 'theme')).toContain('Theme: theme');
  });
});
```

**Step 2: Run — expect FAIL:**

```bash
npx jest src/lib/prompts.test.ts
```

**Step 3: Implement** — in `src/lib/prompts.ts`:

(a) In `EXTRACT_PROMPT`, change the two lines

```
Note Title: {title}
Note Content: {content}
```

to

```
Note Title: {title}
Note Content: {content}
{intent}
```

(b) Add after `EXTRACT_PROMPT`:

```typescript
/**
 * Obsidian feedback loop: the author's own statement of what a note means, injected into
 * EXTRACT_PROMPT's {intent} slot (and the essence context). Empty input -> '' so notes
 * without feedback get today's prompt byte-for-byte (minus the blank placeholder line).
 */
export function buildIntentBlock(intents: string[]): string {
  if (intents.length === 0) return '';
  const bullets = intents.map((t) => `- "${t.replace(/\s+/g, ' ').trim()}"`).join('\n');
  return [
    ``,
    `The author has clarified what this note means to them:`,
    bullets,
    `Weight the author's stated intent over the surface topic when choosing concepts, category, and primary_theme.`,
    ``,
  ].join('\n');
}
```

(c) Extend `buildEssencePrompt` with a trailing optional param `intents: string[] = []`, and inside it (alongside the existing concept/theme pushes):

```typescript
  if (intents.length > 0) {
    contextParts.push(`The author says this note means: ${intents.map((t) => `"${t.replace(/\s+/g, ' ').trim()}"`).join(' | ')}`);
  }
```

**Step 4: Run — expect PASS**, plus the type gate (other EXTRACT_PROMPT users must still compile — `process-llm.ts` is patched next task; until then `{intent}` simply survives as literal text in its output, which only matters at runtime, not compile time):

```bash
npx jest src/lib/prompts.test.ts && npx tsc --noEmit
```

**Step 5: Commit**

```bash
git add src/lib/prompts.ts src/lib/prompts.test.ts
git commit -m "feat(feedback): {intent} slot in EXTRACT_PROMPT + intent context in essence prompt"
```

---

### Task 5: Wire intents into process-llm

**Files:**
- Modify: `src/workflows/process-llm.ts`

No new unit test (the workflow's LLM loop has no jest harness — this is 4 lines of wiring on jest-covered helpers; the dev e2e in Task 8 exercises it end-to-end). `npx tsc --noEmit` is the gate here.

**Step 1: Implement.** In `src/workflows/process-llm.ts`:

(a) Add imports:

```typescript
import { buildIntentBlock } from '../lib/prompts';      // merge into the existing prompts import
import { getIntentTexts, markFeedbackApplied } from '../lib/vault-feedback';
```

(b) Replace the prompt construction (currently `const prompt = EXTRACT_PROMPT.replace('{title}', note.title).replace('{content}', note.content);`) with:

```typescript
      // Obsidian feedback loop: if the author has clarified this note's meaning, carry it
      // into every (re-)derivation — including rebuilds (note_feedback is facts-side).
      const intents = getIntentTexts(db, note.id);
      const prompt = EXTRACT_PROMPT.replace('{title}', note.title)
        .replace('{content}', note.content)
        .replace('{intent}', buildIntentBlock(intents));
```

(c) Immediately after `markProcessed(note.id);` add:

```typescript
      if (intents.length > 0) {
        markFeedbackApplied(db, note.id, new Date().toISOString());
      }
```

(d) Pass intents to the essence prompt — change the `buildEssencePrompt(...)` call's arg list to append `intents`:

```typescript
        const essencePrompt = buildEssencePrompt(
          note.title,
          note.content,
          JSON.stringify(extracted.concepts || []),
          extracted.primary_theme || null,
          intents
        );
```

**Step 2: Gate:**

```bash
npx tsc --noEmit && npm test
```
Expected: clean compile, full suite green.

**Step 3: Commit**

```bash
git add src/workflows/process-llm.ts
git commit -m "feat(feedback): process-llm derives with author intent + stamps applied_at"
```

---

### Task 6: Render — `selene_id` frontmatter + Your-note section + applied blocks

**Files:**
- Modify: `src/lib/obsidian-render.ts`
- Test: `src/lib/obsidian-render.test.ts` (append)

**Step 1: Write the failing tests** — append to `src/lib/obsidian-render.test.ts` (match its existing fixture style; it calls `renderNoteMarkdown(note, parents)` on plain objects):

```typescript
describe('feedback loop rendering', () => {
  const note = {
    id: 42, title: 'T', content: 'body', created_at: '2026-06-01T00:00:00.000Z',
    primary_theme: 'theme', concepts: null, essence: null,
  };

  it('emits selene_id in frontmatter', () => {
    expect(renderNoteMarkdown(note, [])).toMatch(/^selene_id: 42$/m);
  });

  it('always ends with an empty Your-note section (the invitation)', () => {
    const md = renderNoteMarkdown(note, []);
    expect(md.trimEnd().endsWith('## ✍️ Your note')).toBe(true);
  });

  it('renders applied feedback as blockquote + applied-date line', () => {
    const md = renderNoteMarkdown(note, [], [
      { feedback_text: 'a skill I enjoy\nremember it', applied_at: '2026-06-10T12:00:00.000Z' },
    ]);
    expect(md).toContain('> a skill I enjoy\n> remember it\n> — applied 2026-06-10 ✓');
  });

  it('round-trips with the parser: applied blocks are not re-ingested as new feedback', () => {
    const md = renderNoteMarkdown(note, [], [
      { feedback_text: 'old', applied_at: '2026-06-10T12:00:00.000Z' },
    ]);
    expect(parseYourNoteSection(md)).toEqual({ hasSection: true, newFeedback: null });
  });
});
```

Add the needed imports at the top of the test file: `parseYourNoteSection` from `./vault-feedback`.

**Step 2: Run — expect FAIL:**

```bash
npx jest src/lib/obsidian-render.test.ts
```

**Step 3: Implement** — in `src/lib/obsidian-render.ts`:

(a) Import the shared heading (no cycle: vault-feedback imports nothing from this module):

```typescript
import { YOUR_NOTE_HEADING } from './vault-feedback';
```

(b) Add the type and extend the signature:

```typescript
export interface AppliedFeedback {
  feedback_text: string;
  applied_at: string;
}

export function renderNoteMarkdown(
  note: RenderableNote,
  parentClusters: string[],
  appliedFeedback: AppliedFeedback[] = []
): string {
```

(c) In the frontmatter `parts` array, after the `date: ${dateStr}` entry, add:

```typescript
    `selene_id: ${note.id}`,
```

(d) At the end of the function, after the `parentBlock` push and before `return`, add:

```typescript
  // Feedback loop capture surface: ALWAYS present (an empty invitation costs nothing; a missing
  // heading would make the user add it by hand on iPad — friction). Applied history renders as
  // blockquotes, which the parser ignores — only plain text below counts as new feedback.
  parts.push(``, YOUR_NOTE_HEADING);
  for (const fb of appliedFeedback) {
    const quoted = fb.feedback_text.split('\n').map((l) => `> ${l}`).join('\n');
    parts.push(``, `${quoted}\n> — applied ${fb.applied_at.slice(0, 10)} ✓`);
  }
```

**Step 4: Run — expect PASS** (both render suites — the `.db.test.ts` fixtures must still pass; they don't assert full-document equality per the existing tests, but if any do, update their expected strings to include the new frontmatter line + trailing section):

```bash
npx jest src/lib/obsidian-render
```

**Step 5: Commit**

```bash
git add src/lib/obsidian-render.ts src/lib/obsidian-render.test.ts
git commit -m "feat(feedback): render selene_id + Your-note section + applied-✓ blocks"
```

---

### Task 7: Preserve-on-render + feed applied feedback into the reconcile loop

**Files:**
- Modify: `src/lib/obsidian-render.ts` (`reconcileExportedNotes`)
- Test: `src/lib/obsidian-render.db.test.ts` (append)

**Step 1: Write the failing tests** — append to `src/lib/obsidian-render.db.test.ts`, following its existing setup (it drives `reconcileExportedNotes` against `makeTwoFileTestDb` + a temp notes dir; reuse its seed helpers):

```typescript
describe('feedback preserve-on-render', () => {
  it('a rewrite re-appends unprocessed user text from the existing file', () => {
    // seed one processed note; first reconcile writes the file
    // (reuse this suite's existing seeding pattern for captured_notes/processed_notes/note_state)
    reconcileExportedNotes(db, notesDir);
    const file = join(notesDir, /* this suite's filename helper for the seeded note */);

    // user types feedback into the vault file
    writeFileSync(file, readFileSync(file, 'utf-8') + '\nmy new feedback\n', 'utf-8');

    // force a content change (e.g. update essence) so the hash flips and the file rewrites
    db.prepare(`UPDATE processed_notes SET essence = 'new essence' WHERE raw_note_id = ?`).run(noteId);
    reconcileExportedNotes(db, notesDir);

    const after = readFileSync(file, 'utf-8');
    expect(after).toContain('new essence');
    expect(after.trimEnd().endsWith('my new feedback')).toBe(true); // user text survived the rewrite
  });

  it('renders applied feedback from facts.note_feedback', () => {
    db.prepare(
      `INSERT INTO facts.note_feedback (raw_note_id, feedback_text, created_at, applied_at)
       VALUES (?, 'a skill I enjoy', '2026-06-10', '2026-06-10T12:00:00.000Z')`
    ).run(noteId);
    reconcileExportedNotes(db, notesDir);
    const after = readFileSync(join(notesDir, /* filename */), 'utf-8');
    expect(after).toContain('> a skill I enjoy');
    expect(after).toContain('— applied 2026-06-10 ✓');
  });
});
```

(Adapt the seeding/filename details to the suite's existing helpers when writing the real test — the assertions above are the contract.)

**Step 2: Run — expect FAIL:**

```bash
npx jest src/lib/obsidian-render.db.test.ts
```

**Step 3: Implement** — in `reconcileExportedNotes`:

(a) Imports: add `readFileSync` to the fs import; add `parseYourNoteSection` to the vault-feedback import.

(b) Before the notes loop, load applied feedback once:

```typescript
  const feedbackRows = database
    .prepare(
      `SELECT raw_note_id, feedback_text, applied_at FROM facts.note_feedback
       WHERE applied_at IS NOT NULL ORDER BY applied_at ASC, id ASC`
    )
    .all() as Array<{ raw_note_id: number; feedback_text: string; applied_at: string }>;
  const feedbackByNote = new Map<number, AppliedFeedback[]>();
  for (const r of feedbackRows) {
    const list = feedbackByNote.get(r.raw_note_id) ?? [];
    list.push({ feedback_text: r.feedback_text, applied_at: r.applied_at });
    feedbackByNote.set(r.raw_note_id, list);
  }
```

(c) Pass it to the render call:

```typescript
      const markdown = renderNoteMarkdown(note, parentClusters, feedbackByNote.get(note.id) ?? []);
```

(d) Replace the bare `writeFileSync(filePath, markdown, 'utf-8');` with:

```typescript
      // Preserve-on-render: the hash (and skip decision) covers the CANONICAL render only;
      // un-ingested user feedback in the existing file is an additive passthrough, re-appended
      // verbatim so no export/scan ordering can ever clobber the author's words. (It lands back
      // inside the Your-note section because that section is the document's tail.)
      let toWrite = markdown;
      if (existsSync(filePath)) {
        const { newFeedback } = parseYourNoteSection(readFileSync(filePath, 'utf-8'));
        if (newFeedback) toWrite = `${markdown}\n\n${newFeedback}`;
      }
      writeFileSync(filePath, toWrite, 'utf-8');
```

> Why this is safe with the skip logic: if the canonical render is unchanged (hash match + file exists) the file isn't rewritten at all, so user text trivially survives. A rewrite only happens when the render changed, and then the passthrough re-appends any still-unprocessed text.

**Step 4: Run — expect PASS**, then everything:

```bash
npx jest src/lib/obsidian-render && npx tsc --noEmit && npm test
```

**Step 5: Commit**

```bash
git add src/lib/obsidian-render.ts src/lib/obsidian-render.db.test.ts
git commit -m "feat(feedback): preserve-on-render passthrough + applied blocks in reconcile"
```

---

### Task 8: Workflow wrapper + launchd plist + system map

**Files:**
- Create: `src/workflows/vault-feedback.ts`
- Create: `scripts/selene-vault-feedback` (chmod +x)
- Create: `launchd/com.selene.vault-feedback.plist`
- Regenerate: `docs/SYSTEM-MAP.md`

**Step 1: Create `src/workflows/vault-feedback.ts`** (the `@map` comments feed `gen-system-map.ts` — keep them accurate):

```typescript
// @map purpose: Scan vault "Your note" sections → ingest author intent into facts.note_feedback + re-pend notes for re-derivation
// @map reads: Obsidian vault, raw_notes, processed_notes
// @map writes: note_feedback (facts.db), note_state
import { join } from 'path';
import { createWorkflowLogger, db, config } from '../lib';
import { scanVaultFeedback } from '../lib/vault-feedback';

const log = createWorkflowLogger('vault-feedback');

export function vaultFeedback(): ReturnType<typeof scanVaultFeedback> {
  const notesDir = join(config.vaultPath, 'Notes');
  log.info({ notesDir }, 'Scanning vault for author feedback');
  const result = scanVaultFeedback(db, notesDir, new Date().toISOString());
  log.info(result, 'Vault feedback scan complete');
  if (result.unmatched > 0) {
    log.warn({ unmatched: result.unmatched }, 'Files with feedback but no resolvable selene_id (skipped, untouched)');
  }
  return result;
}

// CLI entry point
if (require.main === module) {
  const result = vaultFeedback();
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.errors > 0 ? 1 : 0);
}
```

(Verify `config` and `createWorkflowLogger` are exported from `src/lib/index.ts` — `export-obsidian.ts` imports both, so they are.)

**Step 2: Create `scripts/selene-vault-feedback`** (mirrors `scripts/selene-process-llm`):

```bash
#!/bin/bash
exec /usr/local/bin/npx ts-node src/workflows/vault-feedback.ts
```

```bash
chmod +x scripts/selene-vault-feedback
```

**Step 3: Create `launchd/com.selene.vault-feedback.plist`** — copy the shape of `com.selene.export-obsidian.plist` (it's the one that carries `SELENE_VAULT_PATH`), with `StartInterval` 900:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.vault-feedback</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/chaseeasterling/selene/scripts/selene-vault-feedback</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_ENV</key>
        <string>production</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
        <key>SELENE_VAULT_PATH</key>
        <string>/Users/chaseeasterling/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene</string>
    </dict>

    <key>StartInterval</key>
    <integer>900</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/vault-feedback.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/vault-feedback.error.log</string>
</dict>
</plist>
```

> Check `com.selene.export-obsidian.plist` for any keys this template missed (e.g. `SELENE_FACTS_DB_PATH` if present there) and mirror them. `install-prod.sh` generates `com.selene.prod.vault-feedback` from this canonical plist (entrypoint becomes `dist/workflows/vault-feedback.js`); `install-launchd.sh` picks it up automatically via its `launchd/com.selene.*.plist` glob. Do NOT load it on the dev machine — dev runs no scheduled workflow agents.

**Step 4: Regenerate the system map + verify:**

```bash
npx ts-node scripts/gen-system-map.ts && npx ts-node scripts/gen-system-map.ts --check
```
Expected: `docs/SYSTEM-MAP.md` gains a `vault-feedback` row (purpose + reads/writes from the `@map` comments, 900s schedule from the plist); `--check` exits 0.

**Step 5: Full gate + commit:**

```bash
npx tsc --noEmit && npm test
git add src/workflows/vault-feedback.ts scripts/selene-vault-feedback launchd/com.selene.vault-feedback.plist docs/SYSTEM-MAP.md
git commit -m "feat(feedback): vault-feedback workflow + 15-min launchd agent + system map"
```

> The diagram-sync skill / Stop hook may flag `docs/backend-block-diagrams.md` for the new workflow — update it if prompted.

---

### Task 9: Dev-sandbox e2e (manual verification)

No code — this proves the full loop against the dev environment before review. Requires Ollama running.

**Step 1: Find the dev vault path** (never hardcode it):

```bash
SELENE_ENV=development npx ts-node -e "console.log(require('./src/lib/config').config.vaultPath)"
```

**Step 2: Seed + process + export one dev note** (dev DB must exist — `./scripts/create-dev-db.sh && npx ts-node scripts/seed-dev-data.ts` if not):

```bash
SELENE_ENV=development npx ts-node src/workflows/process-llm.ts
SELENE_ENV=development npx ts-node src/workflows/export-obsidian.ts
```

**Step 3: Verify the rendered note** in `<devVault>/Notes/`: frontmatter has `selene_id: N`; the file ends with `## ✍️ Your note`.

**Step 4: Type feedback** — append a line of plain text under the heading in one note file (pick a note, note its `selene_id`).

**Step 5: Run the loop:**

```bash
SELENE_ENV=development npx ts-node src/workflows/vault-feedback.ts
```
Expected JSON: `ingested: 1`. Then check the dev DB (content-free):

```bash
sqlite3 ~/selene-data-dev/facts.db "SELECT raw_note_id, applied_at IS NULL AS pending_apply FROM note_feedback;"
sqlite3 ~/selene-data-dev/selene.db "SELECT status FROM note_state WHERE raw_note_id = <N>;"
```
Expected: one feedback row (`pending_apply` 1), status `pending`.

**Step 6: Re-derive + re-export:**

```bash
SELENE_ENV=development npx ts-node src/workflows/process-llm.ts
SELENE_ENV=development npx ts-node src/workflows/export-obsidian.ts
```
Expected: the note's filing changed in line with the intent; the vault file now shows the feedback as a `> …` block ending `— applied <today> ✓`; `applied_at` is set. Re-run `vault-feedback` once more → `duplicates: 0, ingested: 0` (the applied block is not re-ingested).

**Step 7: Record the e2e result in BRANCH-STATUS.md** (testing stage checkbox) and commit.

---

### Task 10: User guide + wrap-up docs

**Files:**
- Create: `docs/guides/features/obsidian-feedback.md` (copy `docs/guides/features/_TEMPLATE.md`)
- Modify: `docs/USER-EXPERIENCE.md` (add the guide link)
- Modify: `docs/plans/INDEX.md` (move the design's entry Ready → In Progress at branch start; → note Ph1 state at merge)
- Modify: `BRANCH-STATUS.md` (docs stage checkbox)

**Step 1: Write the guide** following the template's operator-facing structure (Using it → How it works → Configure & customize → Troubleshooting → Related). **Verify every claim against the merged code, not the design doc.** Must cover: where to type (any exported note's `## ✍️ Your note` section, Mac/iPad), the ~15-min + ~5-min timing before the ✓ appears, what blockquotes mean, that feedback is permanent (facts.db, survives rebuild), and the troubleshooting case "my text disappeared" (it can't — preserve-on-render — but the ✓ form moves it into a blockquote) and "no ✓ after 30 min" (check `logs/vault-feedback.error.log`, `selene-inspect counts` for pending backlog, Ollama availability).

**Step 2: Link it from the hub** `docs/USER-EXPERIENCE.md`.

**Step 3: Commit:**

```bash
git add docs/guides/features/obsidian-feedback.md docs/USER-EXPERIENCE.md docs/plans/INDEX.md BRANCH-STATUS.md
git commit -m "docs(feedback): obsidian-feedback user guide + hub link"
```

---

### Task 11: Final verification + review

**Step 1: Full gate from the worktree root:**

```bash
npx tsc --noEmit && npm test && npx ts-node scripts/gen-system-map.ts --check
```
Expected: all green.

**Step 2:** REQUIRED SUB-SKILL: `superpowers:requesting-code-review` against the design doc's acceptance criteria.

**Step 3:** REQUIRED SUB-SKILL: `superpowers:finishing-a-development-branch`.

**Post-merge operator steps (NOT Claude — record in BRANCH-STATUS / hand to user):**
1. Push to origin → deploy-watcher ships within ~5 min, **but** `deploy-prod.sh` only *restarts already-loaded* agents — a new agent requires: `./scripts/install-prod.sh` (generates + loads `com.selene.prod.vault-feedback`).
2. First prod export run rewrites the full corpus (new frontmatter line + section) — ~300 files over 2 hourly runs (writeCap 200). Expected, one-time.
3. Sanity: `npx ts-node scripts/selene-inspect.ts counts` and `tail logs/vault-feedback.log` after the first 15-min tick.

---

## Out of scope (Phase 2 — separate plan, gated on Ph1 data)

Few-shot corrections in `EXTRACT_PROMPT` (last ~5 applied corrections: original text → `original_filing` → intent → corrected filing). The `original_filing` snapshots Phase 1 writes are its training set.
