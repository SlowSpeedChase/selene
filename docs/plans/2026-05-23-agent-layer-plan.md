# Agent Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a scoped, human-in-the-loop agent layer on top of Selene's archivist foundation — starting with the anonymization layer, agent infrastructure, and one working agent (Things Task Metadata Enricher).

**Architecture:** Agents are TypeScript modules that collect data, reason via local Ollama, produce a typed JSON action list, write it to SQLite, then pause. The agent manager orchestrates lifecycles. The web dashboard is the approval surface. Reports are delivered to Apple Notes, Obsidian, and the dashboard.

**Tech Stack:** TypeScript, better-sqlite3, Fastify (existing), Ollama/mistral:7b (existing), osascript (Things + Apple Notes), Node assert (tests)

---

## Task 1: Database Migration — Agent Tables

**Files:**
- Modify: `src/workflows/agent-manager.ts` (create file, migration runs on startup)
- OR create: `scripts/migrate-agent-tables.sql` for manual inspection

The cleanest approach for this codebase: run migrations inline at module load (same pattern as `process-llm.ts` lines 13–18). Create a dedicated migration module.

**Files:**
- Create: `src/lib/agent-db.ts`

**Step 1: Write the failing test**

Create `src/lib/agent-db.test.ts`:

```typescript
import assert from 'assert';
import Database from 'better-sqlite3';
import { join } from 'path';
import { mkdirSync, rmSync, existsSync } from 'fs';

// Use an in-memory DB for tests
process.env.SELENE_ENV = 'test';

async function runTests() {
  // Import after env is set
  const { runAgentMigrations, getAgentRegistry } = await import('./agent-db');

  // Test 1: Tables exist after migration
  {
    const rows = getAgentRegistry();
    assert.ok(Array.isArray(rows), 'getAgentRegistry returns an array');
    console.log('  ✓ agent_registry table exists and is queryable');
  }

  console.log('\nAll agent-db migration tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene
SELENE_ENV=test npx ts-node src/lib/agent-db.test.ts
```

Expected: `Error: Cannot find module './agent-db'`

**Step 3: Create `src/lib/agent-db.ts`**

```typescript
import { db } from './db';
import { logger } from './logger';

// ── Types ──────────────────────────────────────────────────────────────────

export type AgentJobStatus = 'running' | 'paused' | 'complete' | 'error';
export type AgentActionStatus = 'pending' | 'approved' | 'rejected' | 'executing' | 'done';
export type AgentActionTargetType = 'things_task' | 'selene_note' | 'calendar_event';

export interface AgentRegistryRow {
  agent_name: string;
  description: string;
  schedule: string | null;
  allowed_action_types: string; // JSON array
  enabled: number;
  last_run_at: string | null;
  config: string | null; // JSON
}

export interface AgentJobRow {
  id: string;
  agent_name: string;
  status: AgentJobStatus;
  started_at: string;
  completed_at: string | null;
  summary: string | null;
}

export interface AgentActionRow {
  id: string;
  job_id: string;
  action_type: string;
  target_id: string;
  target_type: AgentActionTargetType;
  payload: string; // JSON
  rationale: string;
  confidence: number;
  status: AgentActionStatus;
  created_at: string;
  reviewed_at: string | null;
  executed_at: string | null;
}

export interface AgentReportRow {
  id: string;
  job_id: string;
  title: string;
  body: string; // markdown
  delivered_to: string; // JSON array
  created_at: string;
}

// ── Migrations ─────────────────────────────────────────────────────────────

export function runAgentMigrations(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS agent_registry (
      agent_name TEXT PRIMARY KEY,
      description TEXT NOT NULL,
      schedule TEXT,
      allowed_action_types TEXT NOT NULL DEFAULT '[]',
      enabled INTEGER NOT NULL DEFAULT 1,
      last_run_at TEXT,
      config TEXT
    );

    CREATE TABLE IF NOT EXISTS agent_jobs (
      id TEXT PRIMARY KEY,
      agent_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'running',
      started_at TEXT NOT NULL,
      completed_at TEXT,
      summary TEXT,
      FOREIGN KEY (agent_name) REFERENCES agent_registry(agent_name)
    );

    CREATE TABLE IF NOT EXISTS agent_actions (
      id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL,
      action_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      target_type TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}',
      rationale TEXT NOT NULL,
      confidence REAL NOT NULL DEFAULT 0.5,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      reviewed_at TEXT,
      executed_at TEXT,
      FOREIGN KEY (job_id) REFERENCES agent_jobs(id)
    );

    CREATE TABLE IF NOT EXISTS agent_reports (
      id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      delivered_to TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      FOREIGN KEY (job_id) REFERENCES agent_jobs(id)
    );
  `);

  logger.info('Agent table migrations complete');
}

// ── Registry helpers ───────────────────────────────────────────────────────

export function getAgentRegistry(): AgentRegistryRow[] {
  return db.prepare('SELECT * FROM agent_registry').all() as AgentRegistryRow[];
}

export function getAgentByName(name: string): AgentRegistryRow | undefined {
  return db.prepare('SELECT * FROM agent_registry WHERE agent_name = ?').get(name) as AgentRegistryRow | undefined;
}

export function upsertAgent(agent: {
  agent_name: string;
  description: string;
  schedule?: string;
  allowed_action_types: string[];
  config?: Record<string, unknown>;
}): void {
  db.prepare(`
    INSERT INTO agent_registry (agent_name, description, schedule, allowed_action_types, config)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(agent_name) DO UPDATE SET
      description = excluded.description,
      schedule = excluded.schedule,
      allowed_action_types = excluded.allowed_action_types,
      config = excluded.config
  `).run(
    agent.agent_name,
    agent.description,
    agent.schedule ?? null,
    JSON.stringify(agent.allowed_action_types),
    agent.config ? JSON.stringify(agent.config) : null,
  );
}

export function setAgentEnabled(name: string, enabled: boolean): void {
  db.prepare('UPDATE agent_registry SET enabled = ? WHERE agent_name = ?').run(enabled ? 1 : 0, name);
}

export function touchAgentLastRun(name: string): void {
  db.prepare('UPDATE agent_registry SET last_run_at = ? WHERE agent_name = ?').run(new Date().toISOString(), name);
}

// ── Job helpers ────────────────────────────────────────────────────────────

export function createJob(agentName: string): string {
  const id = `job-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  db.prepare(`
    INSERT INTO agent_jobs (id, agent_name, status, started_at)
    VALUES (?, ?, 'running', ?)
  `).run(id, agentName, new Date().toISOString());
  return id;
}

export function updateJobStatus(id: string, status: AgentJobStatus, summary?: string): void {
  db.prepare(`
    UPDATE agent_jobs SET status = ?, completed_at = ?, summary = ? WHERE id = ?
  `).run(
    status,
    status === 'complete' || status === 'error' ? new Date().toISOString() : null,
    summary ?? null,
    id,
  );
}

export function getJob(id: string): AgentJobRow | undefined {
  return db.prepare('SELECT * FROM agent_jobs WHERE id = ?').get(id) as AgentJobRow | undefined;
}

export function getPausedJobs(): AgentJobRow[] {
  return db.prepare("SELECT * FROM agent_jobs WHERE status = 'paused' ORDER BY started_at ASC").all() as AgentJobRow[];
}

// ── Action helpers ─────────────────────────────────────────────────────────

export function insertActions(actions: Array<{
  job_id: string;
  action_type: string;
  target_id: string;
  target_type: AgentActionTargetType;
  payload: Record<string, unknown>;
  rationale: string;
  confidence: number;
}>): void {
  const stmt = db.prepare(`
    INSERT INTO agent_actions
      (id, job_id, action_type, target_id, target_type, payload, rationale, confidence, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertMany = db.transaction((rows: typeof actions) => {
    for (const row of rows) {
      const id = `action-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      stmt.run(id, row.job_id, row.action_type, row.target_id, row.target_type,
        JSON.stringify(row.payload), row.rationale, row.confidence, new Date().toISOString());
    }
  });

  insertMany(actions);
}

export function getPendingActions(jobId?: string): AgentActionRow[] {
  if (jobId) {
    return db.prepare("SELECT * FROM agent_actions WHERE status = 'pending' AND job_id = ? ORDER BY created_at ASC").all(jobId) as AgentActionRow[];
  }
  return db.prepare("SELECT * FROM agent_actions WHERE status = 'pending' ORDER BY created_at ASC").all() as AgentActionRow[];
}

export function updateActionStatus(id: string, status: AgentActionStatus, payload?: Record<string, unknown>): void {
  const now = new Date().toISOString();
  if (payload) {
    db.prepare(`
      UPDATE agent_actions SET status = ?, payload = ?,
        reviewed_at = CASE WHEN ? IN ('approved','rejected') THEN ? ELSE reviewed_at END,
        executed_at = CASE WHEN ? = 'done' THEN ? ELSE executed_at END
      WHERE id = ?
    `).run(status, JSON.stringify(payload), status, now, status, now, id);
  } else {
    db.prepare(`
      UPDATE agent_actions SET status = ?,
        reviewed_at = CASE WHEN ? IN ('approved','rejected') THEN ? ELSE reviewed_at END,
        executed_at = CASE WHEN ? = 'done' THEN ? ELSE executed_at END
      WHERE id = ?
    `).run(status, status, now, status, now, id);
  }
}

// ── Report helpers ─────────────────────────────────────────────────────────

export function insertReport(report: {
  job_id: string;
  title: string;
  body: string;
}): string {
  const id = `report-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  db.prepare(`
    INSERT INTO agent_reports (id, job_id, title, body, created_at)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, report.job_id, report.title, report.body, new Date().toISOString());
  return id;
}

export function getAllReports(limit = 50): AgentReportRow[] {
  return db.prepare('SELECT * FROM agent_reports ORDER BY created_at DESC LIMIT ?').all(limit) as AgentReportRow[];
}

export function getReportByJobId(jobId: string): AgentReportRow | undefined {
  return db.prepare('SELECT * FROM agent_reports WHERE job_id = ?').get(jobId) as AgentReportRow | undefined;
}

export function markReportDelivered(id: string, channel: string): void {
  const report = db.prepare('SELECT delivered_to FROM agent_reports WHERE id = ?').get(id) as { delivered_to: string } | undefined;
  if (!report) return;
  const channels: string[] = JSON.parse(report.delivered_to);
  if (!channels.includes(channel)) channels.push(channel);
  db.prepare('UPDATE agent_reports SET delivered_to = ? WHERE id = ?').run(JSON.stringify(channels), id);
}
```

**Step 4: Run test to verify it passes**

```bash
SELENE_ENV=test npx ts-node src/lib/agent-db.test.ts
```

Expected: `All agent-db migration tests passed!`

**Step 5: Commit**

```bash
git add src/lib/agent-db.ts src/lib/agent-db.test.ts
git commit -m "feat: add agent database layer with migrations and helpers"
```

---

## Task 2: Anonymization Layer

**Files:**
- Create: `src/lib/anonymize.ts`
- Create: `src/lib/anonymize.test.ts`
- Create: `scripts/anonymize-debug.ts`

**Step 1: Write the failing test**

Create `src/lib/anonymize.test.ts`:

```typescript
import assert from 'assert';

async function runTests() {
  const { anonymize, deanonymize } = await import('./anonymize');

  // Test 1: Email replaced
  {
    const result = anonymize('Contact me at chase@example.com please');
    assert.ok(!result.text.includes('chase@example.com'), 'Email should be replaced');
    assert.ok(result.text.includes('[EMAIL_'), 'Email replaced with token');
    console.log('  ✓ Email addresses are anonymized');
  }

  // Test 2: Phone number replaced
  {
    const result = anonymize('Call me at 555-867-5309');
    assert.ok(!result.text.includes('555-867-5309'), 'Phone should be replaced');
    console.log('  ✓ Phone numbers are anonymized');
  }

  // Test 3: URL replaced
  {
    const result = anonymize('Visit https://my-private-site.com/secret-page for details');
    assert.ok(!result.text.includes('my-private-site.com'), 'URL should be replaced');
    console.log('  ✓ URLs are anonymized');
  }

  // Test 4: Token map allows deanonymization
  {
    const original = 'Email john@test.com or call 555-123-4567';
    const { text, tokenMap } = anonymize(original);
    const restored = deanonymize(text, tokenMap);
    assert.strictEqual(restored, original, 'Deanonymized text matches original');
    console.log('  ✓ Token map allows exact restoration');
  }

  // Test 5: Safe text passes through unchanged
  {
    const safe = 'The quick brown fox jumps over the lazy dog';
    const result = anonymize(safe);
    assert.strictEqual(result.text, safe, 'Safe text unchanged');
    console.log('  ✓ Safe text passes through unchanged');
  }

  // Test 6: Multiple emails get distinct tokens
  {
    const result = anonymize('From: alice@a.com To: bob@b.com');
    assert.ok(result.text.includes('[EMAIL_1]'), 'First email token');
    assert.ok(result.text.includes('[EMAIL_2]'), 'Second email token');
    console.log('  ✓ Multiple instances get distinct tokens');
  }

  console.log('\nAll anonymize tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

```bash
npx ts-node src/lib/anonymize.test.ts
```

Expected: `Error: Cannot find module './anonymize'`

**Step 3: Create `src/lib/anonymize.ts`**

```typescript
export interface AnonymizeResult {
  text: string;
  tokenMap: Record<string, string>; // token → original value
}

// Regex patterns for structured PII
const PII_PATTERNS: Array<{ label: string; pattern: RegExp }> = [
  { label: 'EMAIL',   pattern: /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g },
  { label: 'PHONE',   pattern: /(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}/g },
  { label: 'URL',     pattern: /https?:\/\/[^\s"'<>]+/g },
  { label: 'UUID',    pattern: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi },
];

export function anonymize(text: string): AnonymizeResult {
  const tokenMap: Record<string, string> = {};
  const counters: Record<string, number> = {};
  let result = text;

  for (const { label, pattern } of PII_PATTERNS) {
    // Reset lastIndex for global patterns
    pattern.lastIndex = 0;
    result = result.replace(pattern, (match) => {
      // Check if this exact value already has a token
      const existingToken = Object.keys(tokenMap).find((k) => tokenMap[k] === match);
      if (existingToken) return existingToken;

      counters[label] = (counters[label] ?? 0) + 1;
      const token = `[${label}_${counters[label]}]`;
      tokenMap[token] = match;
      return token;
    });
  }

  return { text: result, tokenMap };
}

export function deanonymize(text: string, tokenMap: Record<string, string>): string {
  let result = text;
  for (const [token, original] of Object.entries(tokenMap)) {
    result = result.split(token).join(original);
  }
  return result;
}

export function anonymizeForDebug(text: string): string {
  return anonymize(text).text;
}
```

**Step 4: Run test to verify it passes**

```bash
npx ts-node src/lib/anonymize.test.ts
```

Expected: `All anonymize tests passed!`

**Step 5: Create `scripts/anonymize-debug.ts`**

This is the debug utility for sharing data with Claude Code safely.

```typescript
#!/usr/bin/env npx ts-node
import { readFileSync } from 'fs';
import { anonymize } from '../src/lib/anonymize';

const source = process.argv[2];

if (!source) {
  console.error('Usage: npx ts-node scripts/anonymize-debug.ts <file-or-stdin>');
  console.error('  npx ts-node scripts/anonymize-debug.ts myfile.txt');
  console.error('  echo "text" | npx ts-node scripts/anonymize-debug.ts -');
  process.exit(1);
}

const raw = source === '-'
  ? readFileSync('/dev/stdin', 'utf-8')
  : readFileSync(source, 'utf-8');

const { text, tokenMap } = anonymize(raw);

console.log('=== ANONYMIZED OUTPUT (safe to share) ===\n');
console.log(text);
console.log('\n=== TOKEN MAP (keep local, do not share) ===');
for (const [token, value] of Object.entries(tokenMap)) {
  console.log(`  ${token} → ${value}`);
}
```

**Step 6: Commit**

```bash
git add src/lib/anonymize.ts src/lib/anonymize.test.ts scripts/anonymize-debug.ts
git commit -m "feat: add anonymization layer with regex PII detection and token map"
```

---

## Task 3: Things AppleScript Bridge

**Files:**
- Create: `src/lib/things.ts`
- Create: `src/lib/things.test.ts`

Things is controlled via AppleScript (`osascript`). The bridge wraps `execSync` calls. Tests verify the bridge module structure; actual Things integration requires manual testing with Things running.

**Step 1: Write the failing test**

Create `src/lib/things.test.ts`:

```typescript
import assert from 'assert';

async function runTests() {
  const things = await import('./things');

  // Test 1: Module exports expected functions
  {
    assert.strictEqual(typeof things.getTasksFromProject, 'function', 'getTasksFromProject exported');
    assert.strictEqual(typeof things.updateTaskNotes, 'function', 'updateTaskNotes exported');
    assert.strictEqual(typeof things.addTagToTask, 'function', 'addTagToTask exported');
    assert.strictEqual(typeof things.buildAppleScript, 'function', 'buildAppleScript exported');
    console.log('  ✓ Things bridge exports all required functions');
  }

  // Test 2: buildAppleScript produces valid AppleScript string
  {
    const script = things.buildAppleScript(`
      tell application "Things3"
        name of first to do
      end tell
    `);
    assert.ok(script.includes('Things3'), 'Script references Things3');
    console.log('  ✓ buildAppleScript produces valid string');
  }

  console.log('\nAll things bridge tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

```bash
npx ts-node src/lib/things.test.ts
```

Expected: `Error: Cannot find module './things'`

**Step 3: Create `src/lib/things.ts`**

```typescript
import { execSync } from 'child_process';
import { logger } from './logger';

const thingsLogger = logger.child({ module: 'things' });

export interface ThingsTask {
  id: string;
  name: string;
  notes: string;
  tags: string[];
  projectName: string;
  dueDate: string | null;
  completed: boolean;
}

export function buildAppleScript(body: string): string {
  return body.trim();
}

function runAppleScript(script: string): string {
  // Escape for shell: wrap in single quotes, escape internal single quotes
  const escaped = script.replace(/'/g, "'\"'\"'");
  try {
    return execSync(`osascript -e '${escaped}'`, {
      timeout: 15000,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (err) {
    const error = err as Error & { stderr?: string };
    thingsLogger.error({ err: error.message, stderr: error.stderr }, 'AppleScript failed');
    throw new Error(`Things AppleScript failed: ${error.message}`);
  }
}

function runAppleScriptFile(script: string): string {
  // For multi-line scripts, use heredoc approach via osascript -e chains
  const lines = script.trim().split('\n');
  const args = lines.map((line) => `-e '${line.replace(/'/g, "'\"'\"'")}'`).join(' ');
  try {
    return execSync(`osascript ${args}`, {
      timeout: 30000,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (err) {
    const error = err as Error & { stderr?: string };
    thingsLogger.error({ err: error.message, stderr: error.stderr }, 'AppleScript failed');
    throw new Error(`Things AppleScript failed: ${error.message}`);
  }
}

export function getTasksFromProject(projectName: string): ThingsTask[] {
  thingsLogger.info({ projectName }, 'Fetching tasks from Things project');

  // AppleScript returns tab-separated fields, one task per line
  // Format: id\tname\tnotes\ttags\tdueDate
  const script = `
tell application "Things3"
  set output to ""
  set theProject to first project whose name is "${projectName.replace(/"/g, '\\"')}"
  repeat with t in to dos of theProject
    set taskId to id of t
    set taskName to name of t
    set taskNotes to notes of t
    set taskTags to tag names of t
    set tagStr to ""
    repeat with tg in taskTags
      set tagStr to tagStr & tg & ","
    end repeat
    set output to output & taskId & "\t" & taskName & "\t" & taskNotes & "\t" & tagStr & "\n"
  end repeat
  return output
end tell
  `.trim();

  try {
    const raw = runAppleScriptFile(script);
    if (!raw) return [];

    return raw
      .split('\n')
      .filter((line) => line.trim())
      .map((line) => {
        const [id, name, notes, tagsRaw] = line.split('\t');
        const tags = tagsRaw
          ? tagsRaw.split(',').map((t) => t.trim()).filter(Boolean)
          : [];
        return { id: id ?? '', name: name ?? '', notes: notes ?? '', tags, projectName, dueDate: null, completed: false };
      });
  } catch (err) {
    thingsLogger.error({ err, projectName }, 'Failed to get tasks from project');
    return [];
  }
}

export function updateTaskNotes(taskId: string, notes: string): boolean {
  thingsLogger.info({ taskId }, 'Updating task notes');

  const escapedNotes = notes.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const script = `
tell application "Things3"
  set t to to do id "${taskId}"
  set notes of t to "${escapedNotes}"
end tell
  `.trim();

  try {
    runAppleScriptFile(script);
    thingsLogger.info({ taskId }, 'Task notes updated');
    return true;
  } catch (err) {
    thingsLogger.error({ err, taskId }, 'Failed to update task notes');
    return false;
  }
}

export function addTagToTask(taskId: string, tagName: string): boolean {
  thingsLogger.info({ taskId, tagName }, 'Adding tag to task');

  const script = `
tell application "Things3"
  set t to to do id "${taskId}"
  set existing to tag names of t
  if "${tagName.replace(/"/g, '\\"')}" is not in existing then
    set tag names of t to existing & {"${tagName.replace(/"/g, '\\"')}"}
  end if
end tell
  `.trim();

  try {
    runAppleScriptFile(script);
    thingsLogger.info({ taskId, tagName }, 'Tag added');
    return true;
  } catch (err) {
    thingsLogger.error({ err, taskId, tagName }, 'Failed to add tag');
    return false;
  }
}
```

**Step 4: Run test to verify it passes**

```bash
npx ts-node src/lib/things.test.ts
```

Expected: `All things bridge tests passed!`

**Step 5: Commit**

```bash
git add src/lib/things.ts src/lib/things.test.ts
git commit -m "feat: add Things AppleScript bridge for task read/write"
```

---

## Task 4: Base Agent Infrastructure

**Files:**
- Create: `src/agents/base-agent.ts`
- Create: `src/agents/base-agent.test.ts`

The base agent provides the shared run loop: collect → reason → queue → pause.

**Step 1: Write the failing test**

Create `src/agents/base-agent.test.ts`:

```typescript
import assert from 'assert';

async function runTests() {
  const { BaseAgent } = await import('./base-agent');

  // Test 1: BaseAgent is a class
  {
    assert.strictEqual(typeof BaseAgent, 'function', 'BaseAgent is a constructor');
    console.log('  ✓ BaseAgent class is exported');
  }

  // Test 2: Validates action types against allowed list
  {
    class TestAgent extends BaseAgent {
      name = 'test-agent';
      allowedActionTypes = ['test.do_something'];
      async collect() { return { items: [] }; }
      async reason(_data: unknown) {
        return [{ action_type: 'test.do_something', target_id: '1', target_type: 'things_task' as const, payload: {}, rationale: 'test', confidence: 0.9 }];
      }
    }
    const agent = new TestAgent();
    assert.ok(agent.validateActionTypes([{ action_type: 'test.do_something', target_id: '1', target_type: 'things_task', payload: {}, rationale: '', confidence: 0.9 }]), 'Valid action passes');
    assert.ok(!agent.validateActionTypes([{ action_type: 'test.forbidden', target_id: '1', target_type: 'things_task', payload: {}, rationale: '', confidence: 0.9 }]), 'Invalid action fails');
    console.log('  ✓ Action type validation works');
  }

  console.log('\nAll base-agent tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

```bash
npx ts-node src/agents/base-agent.test.ts
```

Expected: `Error: Cannot find module './base-agent'`

**Step 3: Create `src/agents/base-agent.ts`**

```typescript
import { logger } from '../lib/logger';
import {
  runAgentMigrations,
  upsertAgent,
  createJob,
  updateJobStatus,
  insertActions,
  insertReport,
  touchAgentLastRun,
  AgentActionTargetType,
} from '../lib/agent-db';

export interface ProposedAction {
  action_type: string;
  target_id: string;
  target_type: AgentActionTargetType;
  payload: Record<string, unknown>;
  rationale: string;
  confidence: number;
}

export abstract class BaseAgent {
  abstract name: string;
  abstract allowedActionTypes: string[];

  protected log = logger.child({ module: 'agent' });

  /** Collect input data from Selene DB and/or external systems */
  abstract collect(): Promise<unknown>;

  /** Ask Ollama to reason over data and return a typed action list */
  abstract reason(data: unknown): Promise<ProposedAction[]>;

  /** Register agent in registry (called once on startup) */
  register(opts: { description: string; schedule?: string; config?: Record<string, unknown> }): void {
    runAgentMigrations();
    upsertAgent({
      agent_name: this.name,
      description: opts.description,
      schedule: opts.schedule,
      allowed_action_types: this.allowedActionTypes,
      config: opts.config,
    });
  }

  /** Validate that all proposed actions use allowed action types */
  validateActionTypes(actions: ProposedAction[]): boolean {
    return actions.every((a) => this.allowedActionTypes.includes(a.action_type));
  }

  /** Full agent run: collect → reason → validate → queue → pause */
  async run(): Promise<{ jobId: string; actionCount: number }> {
    this.log.info({ agent: this.name }, 'Agent run started');
    touchAgentLastRun(this.name);

    const jobId = createJob(this.name);

    try {
      const data = await this.collect();
      this.log.info({ agent: this.name, jobId }, 'Data collected');

      const rawActions = await this.reason(data);
      this.log.info({ agent: this.name, jobId, actionCount: rawActions.length }, 'Reasoning complete');

      const validActions = rawActions.filter((a) => this.allowedActionTypes.includes(a.action_type));
      const invalidCount = rawActions.length - validActions.length;
      if (invalidCount > 0) {
        this.log.warn({ agent: this.name, jobId, invalidCount }, 'Filtered out actions with disallowed types');
      }

      if (validActions.length === 0) {
        updateJobStatus(jobId, 'complete', 'No actions proposed');
        return { jobId, actionCount: 0 };
      }

      insertActions(validActions.map((a) => ({ ...a, job_id: jobId })));

      const report = this.buildReport(jobId, validActions, data);
      insertReport({ job_id: jobId, title: report.title, body: report.body });

      updateJobStatus(jobId, 'paused', `Awaiting approval for ${validActions.length} action(s)`);
      this.log.info({ agent: this.name, jobId, actionCount: validActions.length }, 'Agent paused, awaiting approval');

      return { jobId, actionCount: validActions.length };
    } catch (err) {
      const error = err as Error;
      this.log.error({ agent: this.name, jobId, err: error.message }, 'Agent run failed');
      updateJobStatus(jobId, 'error', error.message);
      throw err;
    }
  }

  /** Override to customize report format */
  buildReport(jobId: string, actions: ProposedAction[], _data: unknown): { title: string; body: string } {
    const lines = actions.map(
      (a) => `- **${a.action_type}** on \`${a.target_id}\` (confidence: ${(a.confidence * 100).toFixed(0)}%)\n  > ${a.rationale}`
    );

    return {
      title: `${this.name} — ${actions.length} proposed action(s)`,
      body: `## ${this.name} Report\n\n**Job:** ${jobId}\n\n### Proposed Actions\n\n${lines.join('\n\n')}`,
    };
  }
}
```

**Step 4: Run test to verify it passes**

```bash
npx ts-node src/agents/base-agent.test.ts
```

Expected: `All base-agent tests passed!`

**Step 5: Commit**

```bash
git add src/agents/base-agent.ts src/agents/base-agent.test.ts
git commit -m "feat: add BaseAgent abstract class with collect/reason/queue/pause loop"
```

---

## Task 5: Process Code — Action Executor

**Files:**
- Create: `src/agents/executor.ts`
- Create: `src/agents/executor.test.ts`

The executor runs approved actions by dispatching to registered handlers. Each handler is a typed function that takes an `AgentActionRow` and executes the real side effect.

**Step 1: Write the failing test**

Create `src/agents/executor.test.ts`:

```typescript
import assert from 'assert';

async function runTests() {
  const { ActionExecutor } = await import('./executor');

  // Test 1: ActionExecutor exists
  {
    assert.strictEqual(typeof ActionExecutor, 'function', 'ActionExecutor is a constructor');
    console.log('  ✓ ActionExecutor is exported');
  }

  // Test 2: Can register and retrieve handlers
  {
    const executor = new ActionExecutor();
    let called = false;
    executor.register('test.action', async (_action) => { called = true; });
    assert.ok(executor.hasHandler('test.action'), 'Handler is registered');
    assert.ok(!executor.hasHandler('test.other'), 'Unknown handler returns false');
    console.log('  ✓ Handlers can be registered and checked');
  }

  // Test 3: Unregistered action type throws
  {
    const executor = new ActionExecutor();
    try {
      await executor.execute({ id: '1', job_id: 'j1', action_type: 'unknown.action', target_id: 't1', target_type: 'things_task', payload: '{}', rationale: '', confidence: 0.9, status: 'approved', created_at: '', reviewed_at: null, executed_at: null });
      assert.fail('Should have thrown');
    } catch (err) {
      const error = err as Error;
      assert.ok(error.message.includes('unknown.action'), 'Error names the unknown action type');
      console.log('  ✓ Unregistered action type throws descriptive error');
    }
  }

  console.log('\nAll executor tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

```bash
npx ts-node src/agents/executor.test.ts
```

Expected: `Error: Cannot find module './executor'`

**Step 3: Create `src/agents/executor.ts`**

```typescript
import { logger } from '../lib/logger';
import { updateActionStatus, AgentActionRow } from '../lib/agent-db';

type ActionHandler = (action: AgentActionRow) => Promise<void>;

export class ActionExecutor {
  private handlers = new Map<string, ActionHandler>();
  private log = logger.child({ module: 'executor' });

  register(actionType: string, handler: ActionHandler): void {
    this.handlers.set(actionType, handler);
  }

  hasHandler(actionType: string): boolean {
    return this.handlers.has(actionType);
  }

  async execute(action: AgentActionRow): Promise<void> {
    const handler = this.handlers.get(action.action_type);
    if (!handler) {
      throw new Error(`No handler registered for action type: ${action.action_type}`);
    }

    this.log.info({ actionId: action.id, actionType: action.action_type, targetId: action.target_id }, 'Executing action');
    updateActionStatus(action.id, 'executing');

    try {
      await handler(action);
      updateActionStatus(action.id, 'done');
      this.log.info({ actionId: action.id }, 'Action executed successfully');
    } catch (err) {
      const error = err as Error;
      this.log.error({ actionId: action.id, err: error.message }, 'Action execution failed');
      // Revert to approved so it can be retried
      updateActionStatus(action.id, 'approved');
      throw err;
    }
  }

  async executeMany(actions: AgentActionRow[]): Promise<{ succeeded: number; failed: number }> {
    let succeeded = 0;
    let failed = 0;

    for (const action of actions) {
      try {
        await this.execute(action);
        succeeded++;
      } catch {
        failed++;
      }
    }

    return { succeeded, failed };
  }
}

// Singleton executor with all Things handlers registered
import { updateTaskNotes, addTagToTask } from '../lib/things';

export const thingsExecutor = new ActionExecutor();

thingsExecutor.register('things.update_notes', async (action) => {
  const payload = JSON.parse(action.payload) as { notes: string };
  const success = updateTaskNotes(action.target_id, payload.notes);
  if (!success) throw new Error(`Failed to update notes for task ${action.target_id}`);
});

thingsExecutor.register('things.add_tag', async (action) => {
  const payload = JSON.parse(action.payload) as { tag: string };
  const success = addTagToTask(action.target_id, payload.tag);
  if (!success) throw new Error(`Failed to add tag to task ${action.target_id}`);
});
```

**Step 4: Run test to verify it passes**

```bash
npx ts-node src/agents/executor.test.ts
```

Expected: `All executor tests passed!`

**Step 5: Commit**

```bash
git add src/agents/executor.ts src/agents/executor.test.ts
git commit -m "feat: add ActionExecutor with Things handler registration"
```

---

## Task 6: Things Task Metadata Enricher Agent

**Files:**
- Create: `src/agents/things-metadata-enricher.ts`
- Create: `src/agents/things-metadata-enricher.test.ts`

This is the first real agent. It reads tasks from a configured Things project, cross-references Selene notes, and asks Ollama to propose tags and notes enrichments.

**Step 1: Write the failing test**

Create `src/agents/things-metadata-enricher.test.ts`:

```typescript
import assert from 'assert';

async function runTests() {
  const { ThingsMetadataEnricher, buildEnrichmentPrompt } = await import('./things-metadata-enricher');

  // Test 1: Agent exports correctly
  {
    const agent = new ThingsMetadataEnricher('Test Project');
    assert.strictEqual(agent.name, 'things-metadata-enricher', 'Name is correct');
    assert.ok(agent.allowedActionTypes.includes('things.update_notes'), 'Allows update_notes');
    assert.ok(agent.allowedActionTypes.includes('things.add_tag'), 'Allows add_tag');
    console.log('  ✓ ThingsMetadataEnricher has correct name and allowed action types');
  }

  // Test 2: buildEnrichmentPrompt includes task name
  {
    const prompt = buildEnrichmentPrompt('Doctor appointment', 'Recent notes about health checks and insurance');
    assert.ok(prompt.includes('Doctor appointment'), 'Prompt includes task name');
    assert.ok(prompt.includes('Recent notes about health checks'), 'Prompt includes related notes');
    console.log('  ✓ Enrichment prompt includes task name and related notes');
  }

  // Test 3: parseOllamaResponse handles valid JSON
  {
    const { parseOllamaResponse } = await import('./things-metadata-enricher');
    const response = '{"tags": ["health", "admin"], "notes": "Annual checkup scheduling"}';
    const parsed = parseOllamaResponse(response);
    assert.deepStrictEqual(parsed?.tags, ['health', 'admin'], 'Tags parsed');
    assert.strictEqual(parsed?.notes, 'Annual checkup scheduling', 'Notes parsed');
    console.log('  ✓ Ollama response parsing works');
  }

  // Test 4: parseOllamaResponse handles malformed response gracefully
  {
    const { parseOllamaResponse } = await import('./things-metadata-enricher');
    const result = parseOllamaResponse('not json at all');
    assert.strictEqual(result, null, 'Returns null for malformed response');
    console.log('  ✓ Malformed Ollama response returns null gracefully');
  }

  console.log('\nAll things-metadata-enricher tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

```bash
npx ts-node src/agents/things-metadata-enricher.test.ts
```

Expected: `Error: Cannot find module './things-metadata-enricher'`

**Step 3: Create `src/agents/things-metadata-enricher.ts`**

```typescript
import { BaseAgent, ProposedAction } from './base-agent';
import { getTasksFromProject, ThingsTask } from '../lib/things';
import { searchNotesKeyword } from '../lib/db';
import { generate } from '../lib/ollama';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'things-metadata-enricher' });

export interface EnrichmentSuggestion {
  tags: string[];
  notes: string;
}

export function buildEnrichmentPrompt(taskName: string, relatedNotes: string): string {
  return `You are a personal knowledge management assistant.

Task: "${taskName}"

Related notes from the user's archive:
${relatedNotes || '(no related notes found)'}

Based on the task name and any related notes, suggest:
1. Tags (1-3 short, lowercase tags that categorize this task)
2. A one-sentence context note (what this task is about, why it matters)

Respond with ONLY valid JSON in this exact format:
{"tags": ["tag1", "tag2"], "notes": "One sentence context note here."}

Do not include any other text.`;
}

export function parseOllamaResponse(response: string): EnrichmentSuggestion | null {
  try {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;
    const parsed = JSON.parse(jsonMatch[0]) as unknown;
    if (
      typeof parsed === 'object' && parsed !== null &&
      'tags' in parsed && Array.isArray((parsed as Record<string, unknown>).tags) &&
      'notes' in parsed && typeof (parsed as Record<string, unknown>).notes === 'string'
    ) {
      return parsed as EnrichmentSuggestion;
    }
    return null;
  } catch {
    return null;
  }
}

interface CollectedData {
  tasks: ThingsTask[];
  projectName: string;
}

export class ThingsMetadataEnricher extends BaseAgent {
  name = 'things-metadata-enricher';
  allowedActionTypes = ['things.update_notes', 'things.add_tag'];

  constructor(private projectName: string) {
    super();
  }

  async collect(): Promise<CollectedData> {
    log.info({ projectName: this.projectName }, 'Collecting tasks from Things');
    const tasks = getTasksFromProject(this.projectName);
    const needsEnrichment = tasks.filter(
      (t) => !t.notes?.trim() || t.tags.length === 0
    );
    log.info({ total: tasks.length, needsEnrichment: needsEnrichment.length }, 'Tasks collected');
    return { tasks: needsEnrichment, projectName: this.projectName };
  }

  async reason(data: unknown): Promise<ProposedAction[]> {
    const { tasks } = data as CollectedData;
    const actions: ProposedAction[] = [];

    for (const task of tasks) {
      log.info({ taskName: task.name }, 'Reasoning about task');

      // Find related notes from Selene archive
      const relatedNotes = searchNotesKeyword(task.name, 5);
      const relatedText = relatedNotes
        .map((n) => `- ${n.title}: ${n.content.slice(0, 200)}`)
        .join('\n');

      const prompt = buildEnrichmentPrompt(task.name, relatedText);

      try {
        const response = await generate(prompt, { temperature: 0.3 });
        const suggestion = parseOllamaResponse(response);

        if (!suggestion) {
          log.warn({ taskName: task.name }, 'Could not parse Ollama response, skipping');
          continue;
        }

        // Propose notes update if task has no notes
        if (!task.notes?.trim() && suggestion.notes) {
          actions.push({
            action_type: 'things.update_notes',
            target_id: task.id,
            target_type: 'things_task',
            payload: { notes: suggestion.notes },
            rationale: `Task has no notes. Suggested: "${suggestion.notes}"`,
            confidence: 0.75,
          });
        }

        // Propose tag additions for missing tags
        for (const tag of suggestion.tags) {
          if (!task.tags.includes(tag)) {
            actions.push({
              action_type: 'things.add_tag',
              target_id: task.id,
              target_type: 'things_task',
              payload: { tag },
              rationale: `Task has no "${tag}" tag. Suggested based on: "${task.name}"`,
              confidence: 0.7,
            });
          }
        }
      } catch (err) {
        log.error({ err, taskName: task.name }, 'Ollama reasoning failed for task');
      }
    }

    return actions;
  }

  buildReport(jobId: string, actions: ProposedAction[], data: unknown): { title: string; body: string } {
    const { tasks, projectName } = data as CollectedData;
    const noteActions = actions.filter((a) => a.action_type === 'things.update_notes');
    const tagActions = actions.filter((a) => a.action_type === 'things.add_tag');

    const actionLines = actions.map((a) => {
      const payload = a.payload as Record<string, string>;
      if (a.action_type === 'things.update_notes') {
        return `- **Add notes** to task \`${a.target_id}\`: "${payload.notes}" (${(a.confidence * 100).toFixed(0)}% confidence)\n  > ${a.rationale}`;
      }
      return `- **Add tag** \`${payload.tag}\` to task \`${a.target_id}\` (${(a.confidence * 100).toFixed(0)}% confidence)\n  > ${a.rationale}`;
    });

    return {
      title: `Things Metadata Enricher — ${projectName} — ${actions.length} proposed actions`,
      body: `## Things Metadata Enricher Report

**Project:** ${projectName}
**Job:** ${jobId}
**Analyzed:** ${tasks.length} tasks needing enrichment
**Proposed:** ${noteActions.length} notes updates, ${tagActions.length} tag additions

### Proposed Actions

${actionLines.join('\n\n')}

---
*Review and approve in the Selene dashboard at http://localhost:5678/dashboard*`,
    };
  }
}

// CLI entry point
if (require.main === module) {
  const projectName = process.argv[2];
  if (!projectName) {
    console.error('Usage: npx ts-node src/agents/things-metadata-enricher.ts "Project Name"');
    process.exit(1);
  }

  const agent = new ThingsMetadataEnricher(projectName);
  agent.run()
    .then(({ jobId, actionCount }) => {
      console.log(`Agent run complete. Job: ${jobId}, Actions: ${actionCount}`);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Agent run failed:', err);
      process.exit(1);
    });
}
```

**Step 4: Run test to verify it passes**

```bash
npx ts-node src/agents/things-metadata-enricher.test.ts
```

Expected: `All things-metadata-enricher tests passed!`

**Step 5: Manual integration test (requires Things3 running)**

```bash
npx ts-node src/agents/things-metadata-enricher.ts "Your Project Name"
```

Then check the database:
```bash
sqlite3 ~/selene-data/selene.db "SELECT id, agent_name, status, summary FROM agent_jobs ORDER BY started_at DESC LIMIT 3;"
sqlite3 ~/selene-data/selene.db "SELECT id, action_type, target_id, rationale, status FROM agent_actions ORDER BY created_at DESC LIMIT 10;"
```

**Step 6: Commit**

```bash
git add src/agents/things-metadata-enricher.ts src/agents/things-metadata-enricher.test.ts
git commit -m "feat: add Things Task Metadata Enricher agent"
```

---

## Task 7: Agent Manager Service

**Files:**
- Create: `src/workflows/agent-manager.ts`

The agent manager runs as a persistent service. It polls for paused jobs that have been waiting too long and re-surfaces them. It registers known agents on startup. It does not run agents itself — agents run on their own launchd schedules.

**Step 1: Create `src/workflows/agent-manager.ts`**

No test step here — this is a service entrypoint with no pure functions to unit test. Test it by running it and checking logs.

```typescript
import { createWorkflowLogger } from '../lib/logger';
import {
  runAgentMigrations,
  getPausedJobs,
  getAllReports,
  markReportDelivered,
  getReportByJobId,
} from '../lib/agent-db';
import { ThingsMetadataEnricher } from '../agents/things-metadata-enricher';
import { execSync } from 'child_process';

const log = createWorkflowLogger('agent-manager');

const ESCALATION_THRESHOLD_MS = 4 * 60 * 60 * 1000; // 4 hours

function sendMacOSNotification(title: string, body: string): void {
  try {
    const escaped = body.replace(/"/g, '\\"');
    execSync(`osascript -e 'display notification "${escaped}" with title "${title}"'`, { timeout: 5000 });
  } catch (err) {
    log.warn({ err }, 'macOS notification failed');
  }
}

async function deliverPendingReports(): Promise<void> {
  const reports = getAllReports(20);

  for (const report of reports) {
    const delivered: string[] = JSON.parse(report.delivered_to);

    // Apple Notes delivery
    if (!delivered.includes('apple-notes')) {
      try {
        await deliverToAppleNotes(report);
        markReportDelivered(report.id, 'apple-notes');
        log.info({ reportId: report.id }, 'Delivered to Apple Notes');
      } catch (err) {
        log.error({ err, reportId: report.id }, 'Apple Notes delivery failed');
      }
    }

    // Obsidian delivery
    if (!delivered.includes('obsidian')) {
      try {
        await deliverToObsidian(report);
        markReportDelivered(report.id, 'obsidian');
        log.info({ reportId: report.id }, 'Delivered to Obsidian');
      } catch (err) {
        log.error({ err, reportId: report.id }, 'Obsidian delivery failed');
      }
    }
  }
}

async function deliverToAppleNotes(report: { id: string; title: string; body: string }): Promise<void> {
  const escaped = report.body
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/'/g, "'\"'\"'")
    .replace(/\n/g, '\\n');

  const noteName = `Selene Agent: ${report.title.split(' — ')[0]}`;
  const script = `osascript -e 'tell application "Notes"' \
    -e 'set noteName to "${noteName.replace(/'/g, "'\"'\"'")}"' \
    -e 'set noteBody to "${escaped}"' \
    -e 'try' \
    -e 'set targetNote to first note whose name is noteName' \
    -e 'set body of targetNote to body of targetNote & "<br><hr><br>" & noteBody' \
    -e 'on error' \
    -e 'make new note with properties {name:noteName, body:noteBody}' \
    -e 'end try' \
    -e 'end tell'`;

  execSync(script, { timeout: 15000, stdio: 'pipe' });
}

async function deliverToObsidian(report: { id: string; title: string; body: string; created_at: string; job_id: string }): Promise<void> {
  const { config } = await import('../lib/config');
  const { writeFileSync, mkdirSync } = await import('fs');
  const { join } = await import('path');

  const dir = join(config.vaultPath, 'agent-reports');
  mkdirSync(dir, { recursive: true });

  const date = report.created_at.split('T')[0];
  const agentName = report.job_id.split('-').slice(2).join('-');
  const filename = `${date}-${agentName}.md`;

  writeFileSync(join(dir, filename), report.body, 'utf-8');
}

async function checkEscalations(): Promise<void> {
  const pausedJobs = getPausedJobs();
  const now = Date.now();

  for (const job of pausedJobs) {
    const pausedMs = now - new Date(job.started_at).getTime();
    if (pausedMs > ESCALATION_THRESHOLD_MS) {
      const report = getReportByJobId(job.id);
      if (report) {
        const delivered: string[] = JSON.parse(report.delivered_to);
        if (!delivered.includes('escalated')) {
          sendMacOSNotification(
            'Selene: Approval Needed',
            `${job.agent_name} has been waiting ${Math.round(pausedMs / 3600000)}h for your review.`
          );
          markReportDelivered(report.id, 'escalated');
          log.info({ jobId: job.id, agent: job.agent_name }, 'Escalation notification sent');
        }
      }
    }
  }
}

function registerKnownAgents(): void {
  // Register the Things Metadata Enricher agent
  // The project name is configured via environment variable
  const projectName = process.env.THINGS_ENRICHER_PROJECT || 'Inbox';
  const agent = new ThingsMetadataEnricher(projectName);
  agent.register({
    description: 'Enriches Things tasks with metadata (tags, notes) by cross-referencing the Selene note archive',
    schedule: '0 */4 * * *', // Every 4 hours (informational — launchd controls actual schedule)
    config: { projectName },
  });

  log.info({ projectName }, 'Registered things-metadata-enricher');
}

async function main(): Promise<void> {
  log.info('Agent manager starting');

  runAgentMigrations();
  registerKnownAgents();

  // Deliver any pending reports
  await deliverPendingReports();

  // Check for jobs needing escalation
  await checkEscalations();

  log.info('Agent manager run complete');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    log.error({ err }, 'Agent manager failed');
    process.exit(1);
  });
```

**Step 2: Run manually to verify**

```bash
npx ts-node src/workflows/agent-manager.ts
```

Expected: Log output showing migration, agent registration, report delivery check, escalation check, and exit.

**Step 3: Commit**

```bash
git add src/workflows/agent-manager.ts
git commit -m "feat: add agent manager service with delivery and escalation"
```

---

## Task 8: Web Dashboard — API Routes

**Files:**
- Create: `src/routes/agents.ts`
- Modify: `src/server.ts`

The dashboard API handles approval/rejection of actions and agent control. HTML is in Task 9.

**Step 1: Create `src/routes/agents.ts`**

```typescript
import type { FastifyInstance } from 'fastify';
import {
  getAgentRegistry,
  getAgentByName,
  setAgentEnabled,
  getPausedJobs,
  getPendingActions,
  updateActionStatus,
  getAllReports,
  AgentActionRow,
} from '../lib/agent-db';
import { thingsExecutor } from '../agents/executor';
import { logger } from '../lib';

const log = logger.child({ module: 'agents-route' });

export async function agentRoutes(fastify: FastifyInstance): Promise<void> {

  // GET /agents/status — all agent status
  fastify.get('/agents/status', async () => {
    const registry = getAgentRegistry();
    const pausedJobs = getPausedJobs();
    const pendingActions = getPendingActions();

    return {
      agents: registry,
      pausedJobCount: pausedJobs.length,
      pendingActionCount: pendingActions.length,
    };
  });

  // POST /agents/:name/enable — enable agent
  fastify.post<{ Params: { name: string } }>('/agents/:name/enable', async (request, reply) => {
    const agent = getAgentByName(request.params.name);
    if (!agent) { reply.status(404); return { error: 'Agent not found' }; }
    setAgentEnabled(request.params.name, true);
    return { ok: true };
  });

  // POST /agents/:name/disable — disable agent
  fastify.post<{ Params: { name: string } }>('/agents/:name/disable', async (request, reply) => {
    const agent = getAgentByName(request.params.name);
    if (!agent) { reply.status(404); return { error: 'Agent not found' }; }
    setAgentEnabled(request.params.name, false);
    return { ok: true };
  });

  // GET /agents/actions/pending — all pending actions
  fastify.get('/agents/actions/pending', async () => {
    return { actions: getPendingActions() };
  });

  // POST /agents/actions/:id/approve — approve an action
  fastify.post<{ Params: { id: string } }>('/agents/actions/:id/approve', async (request, reply) => {
    updateActionStatus(request.params.id, 'approved');

    // Execute immediately
    const actions = getPendingActions();
    const action = actions.find(() => false); // already updated — re-fetch approved
    void executeApproved(request.params.id);

    return { ok: true };
  });

  // POST /agents/actions/:id/reject — reject an action
  fastify.post<{ Params: { id: string } }>('/agents/actions/:id/reject', async (request, reply) => {
    updateActionStatus(request.params.id, 'rejected');
    return { ok: true };
  });

  // PUT /agents/actions/:id — edit payload then approve
  fastify.put<{
    Params: { id: string };
    Body: { payload: Record<string, unknown> };
  }>('/agents/actions/:id', async (request, reply) => {
    updateActionStatus(request.params.id, 'approved', request.body.payload);
    void executeApproved(request.params.id);
    return { ok: true };
  });

  // GET /agents/reports — all reports
  fastify.get('/agents/reports', async () => {
    return { reports: getAllReports(50) };
  });
}

async function executeApproved(actionId: string): Promise<void> {
  // Re-fetch the action after approval
  const { db } = await import('../lib/db');
  const action = db.prepare("SELECT * FROM agent_actions WHERE id = ? AND status = 'approved'").get(actionId) as AgentActionRow | undefined;
  if (!action) return;

  try {
    await thingsExecutor.execute(action);
    log.info({ actionId }, 'Action executed after approval');
  } catch (err) {
    log.error({ err, actionId }, 'Action execution failed after approval');
  }
}
```

**Step 2: Register routes in `src/server.ts`**

Add after the existing route registrations (before `start()`):

```typescript
import { agentRoutes } from './routes/agents';

// Agent routes
server.register(agentRoutes);
```

**Step 3: Run server and test routes**

```bash
npx ts-node src/server.ts &
curl http://localhost:5678/agents/status
```

Expected: JSON with agents array and counts.

Kill the test server: `kill %1`

**Step 4: Commit**

```bash
git add src/routes/agents.ts src/server.ts
git commit -m "feat: add agent API routes for approval, rejection, and status"
```

---

## Task 9: Web Dashboard — HTML Views

**Files:**
- Create: `src/routes/dashboard.ts`
- Modify: `src/server.ts`

Server-rendered HTML dashboard. No build pipeline — vanilla HTML/CSS served from Fastify. Accessible at `http://localhost:5678/dashboard`.

**Step 1: Create `src/routes/dashboard.ts`**

```typescript
import type { FastifyInstance } from 'fastify';
import {
  getAgentRegistry,
  getPausedJobs,
  getPendingActions,
  getAllReports,
  AgentActionRow,
  AgentJobRow,
  AgentRegistryRow,
  AgentReportRow,
} from '../lib/agent-db';

function html(content: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Selene</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f5f5; color: #1a1a1a; }
    nav { background: #fff; border-bottom: 1px solid #e0e0e0; padding: 12px 24px; display: flex; gap: 24px; align-items: center; }
    nav a { text-decoration: none; color: #666; font-size: 14px; }
    nav a.active, nav a:hover { color: #000; }
    nav .brand { font-weight: 600; color: #000; margin-right: 8px; }
    main { max-width: 900px; margin: 32px auto; padding: 0 24px; }
    h1 { font-size: 22px; font-weight: 600; margin-bottom: 24px; }
    h2 { font-size: 16px; font-weight: 600; margin-bottom: 12px; color: #333; }
    .card { background: #fff; border: 1px solid #e0e0e0; border-radius: 8px; padding: 20px; margin-bottom: 16px; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 100px; font-size: 12px; font-weight: 500; }
    .badge-pending { background: #fff3cd; color: #856404; }
    .badge-running { background: #d1ecf1; color: #0c5460; }
    .badge-paused  { background: #f8d7da; color: #721c24; }
    .badge-done    { background: #d4edda; color: #155724; }
    .badge-enabled { background: #d4edda; color: #155724; }
    .badge-disabled { background: #f5f5f5; color: #666; }
    .action-card { border: 1px solid #e0e0e0; border-radius: 6px; padding: 14px 16px; margin-bottom: 10px; }
    .action-meta { font-size: 12px; color: #666; margin-bottom: 6px; }
    .action-rationale { font-size: 13px; color: #444; margin: 6px 0; }
    .confidence { font-size: 12px; color: #888; }
    .btn { display: inline-block; padding: 6px 14px; border-radius: 6px; font-size: 13px; font-weight: 500; cursor: pointer; border: none; text-decoration: none; }
    .btn-approve { background: #198754; color: #fff; }
    .btn-reject  { background: #fff; color: #dc3545; border: 1px solid #dc3545; }
    .btn-approve:hover { background: #157347; }
    .btn-reject:hover  { background: #dc3545; color: #fff; }
    .btn-group { display: flex; gap: 8px; margin-top: 10px; }
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
    .stat { font-size: 28px; font-weight: 700; }
    .stat-label { font-size: 13px; color: #666; margin-top: 2px; }
    pre { background: #f8f8f8; border: 1px solid #e0e0e0; border-radius: 4px; padding: 10px; font-size: 12px; overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th { text-align: left; padding: 8px 10px; border-bottom: 2px solid #e0e0e0; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.05em; }
    td { padding: 8px 10px; border-bottom: 1px solid #f0f0f0; }
    .report-body { white-space: pre-wrap; font-size: 13px; line-height: 1.6; }
    .empty { color: #999; font-size: 14px; padding: 20px 0; }
  </style>
</head>
<body>
  <nav>
    <span class="brand">Selene</span>
    <a href="/dashboard">Home</a>
    <a href="/dashboard/queue">Approval Queue</a>
    <a href="/dashboard/reports">Reports</a>
    <a href="/dashboard/agents">Agents</a>
  </nav>
  <main>${content}</main>
</body>
</html>`;
}

function badgeStatus(status: string): string {
  const classes: Record<string, string> = {
    pending: 'badge-pending', running: 'badge-running', paused: 'badge-paused',
    complete: 'badge-done', done: 'badge-done', approved: 'badge-done',
    rejected: 'badge-disabled', error: 'badge-paused',
  };
  return `<span class="badge ${classes[status] ?? 'badge-pending'}">${status}</span>`;
}

export async function dashboardRoutes(fastify: FastifyInstance): Promise<void> {

  // Home
  fastify.get('/dashboard', async (_req, reply) => {
    const agents = getAgentRegistry();
    const pausedJobs = getPausedJobs();
    const pendingActions = getPendingActions();

    const agentCards = agents.map((a: AgentRegistryRow) => `
      <div class="card">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div>
            <strong>${a.agent_name}</strong>
            <span class="badge ${a.enabled ? 'badge-enabled' : 'badge-disabled'}" style="margin-left:8px">${a.enabled ? 'enabled' : 'disabled'}</span>
          </div>
          <div style="font-size:12px;color:#888">Last run: ${a.last_run_at ? new Date(a.last_run_at).toLocaleString() : 'never'}</div>
        </div>
        <div style="font-size:13px;color:#555;margin-top:6px">${a.description}</div>
      </div>
    `).join('');

    reply.type('text/html');
    return html(`
      <h1>Selene Dashboard</h1>
      <div class="grid-2" style="margin-bottom:24px">
        <div class="card">
          <div class="stat">${pendingActions.length}</div>
          <div class="stat-label">Actions awaiting approval</div>
          ${pendingActions.length > 0 ? '<a href="/dashboard/queue" class="btn btn-approve" style="margin-top:12px;display:inline-block">Review Queue</a>' : ''}
        </div>
        <div class="card">
          <div class="stat">${pausedJobs.length}</div>
          <div class="stat-label">Jobs paused (awaiting input)</div>
        </div>
      </div>
      <h2>Agents</h2>
      ${agentCards || '<p class="empty">No agents registered yet.</p>'}
    `);
  });

  // Approval Queue
  fastify.get('/dashboard/queue', async (_req, reply) => {
    const actions = getPendingActions();

    const actionCards = actions.map((a: AgentActionRow) => {
      const payload = JSON.parse(a.payload) as Record<string, unknown>;
      return `
        <div class="action-card">
          <div class="action-meta">${badgeStatus(a.status)} &nbsp; <strong>${a.action_type}</strong> on <code>${a.target_id}</code></div>
          <div class="action-rationale">${a.rationale}</div>
          <div class="confidence">Confidence: ${(a.confidence * 100).toFixed(0)}%</div>
          <pre>${JSON.stringify(payload, null, 2)}</pre>
          <div class="btn-group">
            <button class="btn btn-approve" onclick="approveAction('${a.id}')">Approve</button>
            <button class="btn btn-reject"  onclick="rejectAction('${a.id}')">Reject</button>
          </div>
        </div>
      `;
    }).join('');

    reply.type('text/html');
    return html(`
      <h1>Approval Queue <span style="font-size:16px;font-weight:400;color:#666">${actions.length} pending</span></h1>
      ${actionCards || '<p class="empty">No pending actions. Agents are up to date.</p>'}
      <script>
        async function approveAction(id) {
          await fetch('/agents/actions/' + id + '/approve', { method: 'POST' });
          location.reload();
        }
        async function rejectAction(id) {
          await fetch('/agents/actions/' + id + '/reject', { method: 'POST' });
          location.reload();
        }
      </script>
    `);
  });

  // Reports
  fastify.get('/dashboard/reports', async (_req, reply) => {
    const reports = getAllReports(50);

    const reportCards = reports.map((r: AgentReportRow) => `
      <div class="card">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
          <strong>${r.title}</strong>
          <span style="font-size:12px;color:#888">${new Date(r.created_at).toLocaleString()}</span>
        </div>
        <div class="report-body">${r.body}</div>
      </div>
    `).join('');

    reply.type('text/html');
    return html(`
      <h1>Agent Reports</h1>
      ${reportCards || '<p class="empty">No reports yet. Agents haven\'t run.</p>'}
    `);
  });

  // Agents management
  fastify.get('/dashboard/agents', async (_req, reply) => {
    const agents = getAgentRegistry();

    const rows = agents.map((a: AgentRegistryRow) => `
      <tr>
        <td><strong>${a.agent_name}</strong></td>
        <td>${a.description}</td>
        <td>${badgeStatus(a.enabled ? 'enabled' : 'disabled')}</td>
        <td>${a.last_run_at ? new Date(a.last_run_at).toLocaleString() : '—'}</td>
        <td>
          ${a.enabled
            ? `<button class="btn btn-reject" onclick="setEnabled('${a.agent_name}', false)">Disable</button>`
            : `<button class="btn btn-approve" onclick="setEnabled('${a.agent_name}', true)">Enable</button>`
          }
        </td>
      </tr>
    `).join('');

    reply.type('text/html');
    return html(`
      <h1>Agent Manager</h1>
      <div class="card">
        <table>
          <thead><tr><th>Agent</th><th>Description</th><th>Status</th><th>Last Run</th><th>Actions</th></tr></thead>
          <tbody>${rows || '<tr><td colspan="5" class="empty">No agents registered</td></tr>'}</tbody>
        </table>
      </div>
      <script>
        async function setEnabled(name, enabled) {
          await fetch('/agents/' + name + '/' + (enabled ? 'enable' : 'disable'), { method: 'POST' });
          location.reload();
        }
      </script>
    `);
  });
}
```

**Step 2: Register dashboard routes in `src/server.ts`**

```typescript
import { dashboardRoutes } from './routes/dashboard';

// Dashboard routes
server.register(dashboardRoutes);
```

**Step 3: Start server and verify**

```bash
npx ts-node src/server.ts &
open http://localhost:5678/dashboard
```

Verify all four views load without errors. Kill test server: `kill %1`

**Step 4: Commit**

```bash
git add src/routes/dashboard.ts src/server.ts
git commit -m "feat: add web dashboard with home, approval queue, reports, and agent manager views"
```

---

## Task 10: Launchd Agent for Agent Manager

**Files:**
- Create: `launchd/com.selene.agent-manager.plist`
- Create: `scripts/selene-agent-manager`
- Modify: `scripts/install-launchd.sh`

The agent manager runs every 15 minutes — delivers pending reports and checks escalations.

**Step 1: Create `scripts/selene-agent-manager`**

```bash
#!/bin/bash
set -e
cd /Users/chaseeasterling/selene
exec /usr/local/bin/npx ts-node src/workflows/agent-manager.ts
```

Make it executable:

```bash
chmod +x scripts/selene-agent-manager
```

**Step 2: Create `launchd/com.selene.agent-manager.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.agent-manager</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/chaseeasterling/selene/scripts/selene-agent-manager</string>
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
        <key>THINGS_ENRICHER_PROJECT</key>
        <string>Inbox</string>
    </dict>

    <key>StartInterval</key>
    <integer>900</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/agent-manager.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/agent-manager.error.log</string>
</dict>
</plist>
```

**Step 3: Add to `scripts/install-launchd.sh`**

Find the block that copies and loads plists. Add the agent-manager to the list:

```bash
# In the array of agents to install:
"com.selene.agent-manager"
```

The exact edit depends on the current structure of `install-launchd.sh`. Read the file first and follow the existing pattern.

**Step 4: Install manually to test**

```bash
cp launchd/com.selene.agent-manager.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.selene.agent-manager.plist
launchctl list | grep selene
```

Expected: `com.selene.agent-manager` appears in the list.

**Step 5: Check logs**

```bash
tail -f logs/agent-manager.log | npx pino-pretty
```

**Step 6: Commit**

```bash
git add launchd/com.selene.agent-manager.plist scripts/selene-agent-manager scripts/install-launchd.sh
git commit -m "feat: add launchd agent for agent manager (runs every 15 minutes)"
```

---

## Task 11: Export lib index

Update `src/lib/index.ts` to export the new modules so they're importable from `'../lib'`.

**Step 1: Read current index**

```bash
cat src/lib/index.ts
```

**Step 2: Add new exports**

Add to the existing barrel export file:

```typescript
export * from './anonymize';
export * from './agent-db';
export * from './things';
```

**Step 3: Verify no import errors**

```bash
npx tsc --noEmit
```

Expected: No errors (or only pre-existing errors unrelated to new code).

**Step 4: Commit**

```bash
git add src/lib/index.ts
git commit -m "chore: export anonymize, agent-db, and things from lib index"
```

---

## End-to-End Verification

After all tasks complete, verify the full loop works:

**1. Run migrations and register agents**
```bash
npx ts-node src/workflows/agent-manager.ts
```

**2. Run the enricher agent on a test project**
```bash
npx ts-node src/agents/things-metadata-enricher.ts "Your Project Name"
```

**3. Check the job was created**
```bash
sqlite3 ~/selene-data/selene.db "SELECT id, agent_name, status FROM agent_jobs ORDER BY started_at DESC LIMIT 3;"
```

**4. Check actions were proposed**
```bash
sqlite3 ~/selene-data/selene.db "SELECT action_type, target_id, status, rationale FROM agent_actions ORDER BY created_at DESC LIMIT 10;"
```

**5. Open dashboard and approve an action**
```bash
npx ts-node src/server.ts &
open http://localhost:5678/dashboard/queue
```

**6. Verify action executed in Things**

Open Things3 and check the task was updated.

**7. Test anonymize debug script**
```bash
echo "Call me at 555-123-4567 or email test@example.com" | npx ts-node scripts/anonymize-debug.ts -
```

Expected: Anonymized output with token map.
