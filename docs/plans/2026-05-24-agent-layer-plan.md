# Agent Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a human-in-the-loop agent layer on top of Selene's archive — local Ollama reasoning, typed action proposals, approval queue, web dashboard, and a first agent (Things Task Metadata Enricher).

**Architecture:** Agents are narrowly scoped TypeScript modules that read data, call Ollama for a JSON action list, write proposed actions to SQLite with status `pending`, and pause. A persistent agent-manager service orchestrates runs, enforces the action vocabulary, escalates stale approvals, and provides Fastify API routes. A web dashboard at `/dashboard` handles approvals, reports, and agent control.

**Tech Stack:** TypeScript, Fastify, better-sqlite3, Ollama (mistral:7b), AppleScript (Things), launchd, Node `assert` tests

**Design Doc:** `docs/plans/2026-05-23-agent-layer-design.md`

---

## Task 1: TypeScript Types for Agent Layer

**Files:**
- Create: `src/types/agents.ts`
- Modify: `src/types/index.ts`

**Step 1: Create `src/types/agents.ts`**

```typescript
export type AgentStatus = 'running' | 'paused' | 'complete' | 'error';
export type ActionStatus = 'pending' | 'approved' | 'rejected' | 'executing' | 'done';
export type TargetType = 'things_task' | 'selene_note' | 'calendar_event';

// things-enricher specific action types
export type ThingsActionType = 'things.update_notes' | 'things.add_tag';
export type ActionType = ThingsActionType; // extend as agents are added

export interface AgentRegistry {
  agent_name: string;
  description: string;
  schedule: string | null;
  allowed_action_types: string; // JSON array
  enabled: number;              // 0 | 1
  last_run_at: string | null;
  config: string | null;        // JSON, agent-specific
}

export interface AgentJob {
  id: string;
  agent_name: string;
  status: AgentStatus;
  started_at: string;
  completed_at: string | null;
  summary: string | null;
}

export interface AgentAction {
  id: string;
  job_id: string;
  action_type: ActionType;
  target_id: string;
  target_type: TargetType;
  payload: string;              // JSON
  rationale: string;
  confidence: number;           // 0.0–1.0
  status: ActionStatus;
  created_at: string;
  reviewed_at: string | null;
  executed_at: string | null;
}

export interface AgentReport {
  id: string;
  job_id: string;
  title: string;
  body: string;                 // markdown
  delivered_to: string;         // JSON array of channels
  created_at: string;
}

// What Ollama must return per action (parsed from response)
export interface ProposedAction {
  action_type: ActionType;
  target_id: string;
  target_type: TargetType;
  payload: Record<string, unknown>;
  rationale: string;
  confidence: number;
}
```

**Step 2: Re-export from `src/types/index.ts`**

Add at the bottom of the existing `src/types/index.ts`:
```typescript
export * from './agents';
```

**Step 3: Write type test**

Create `src/types/agents.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  const types = await import('./agents');

  // Verify key exports exist
  {
    assert.strictEqual(typeof types, 'object');
    console.log('  ✓ agents types module loads');
  }

  console.log('\nAll agent type tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 4: Run test**
```bash
cd /Users/chaseeasterling/selene
npx ts-node src/types/agents.test.ts
```
Expected: `All agent type tests passed!`

**Step 5: Commit**
```bash
git add src/types/agents.ts src/types/agents.test.ts src/types/index.ts
git commit -m "feat(agents): add TypeScript types for agent layer"
```

---

## Task 2: Database Migration — Agent Tables

**Files:**
- Create: `src/lib/agent-migrate.ts`

**Step 1: Write `src/lib/agent-migrate.ts`**

```typescript
import { db } from './db';

export function migrateAgentTables(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS agent_registry (
      agent_name TEXT PRIMARY KEY,
      description TEXT NOT NULL,
      schedule TEXT,
      allowed_action_types TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      last_run_at TEXT,
      config TEXT
    );

    CREATE TABLE IF NOT EXISTS agent_jobs (
      id TEXT PRIMARY KEY,
      agent_name TEXT NOT NULL,
      status TEXT NOT NULL,
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
      payload TEXT NOT NULL,
      rationale TEXT NOT NULL,
      confidence REAL NOT NULL,
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
}
```

**Step 2: Write migration test**

Create `src/lib/agent-migrate.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  const { migrateAgentTables } = await import('./agent-migrate');
  const { db } = await import('./db');

  // Run migration (idempotent)
  migrateAgentTables();
  migrateAgentTables(); // second call must not throw

  // Verify all four tables exist
  const tables = ['agent_registry', 'agent_jobs', 'agent_actions', 'agent_reports'];
  for (const table of tables) {
    const row = db.prepare(
      `SELECT name FROM sqlite_master WHERE type='table' AND name=?`
    ).get(table);
    assert.ok(row, `Table ${table} should exist`);
    console.log(`  ✓ Table ${table} exists`);
  }

  console.log('\nAll migration tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 3: Run test**
```bash
npx ts-node src/lib/agent-migrate.test.ts
```
Expected: 4 table confirmations + `All migration tests passed!`

**Step 4: Commit**
```bash
git add src/lib/agent-migrate.ts src/lib/agent-migrate.test.ts
git commit -m "feat(agents): add SQLite migration for agent tables"
```

---

## Task 3: Agent Database Helpers

**Files:**
- Create: `src/lib/agent-db.ts`

**Step 1: Write `src/lib/agent-db.ts`**

```typescript
import { randomUUID } from 'crypto';
import { db } from './db';
import { migrateAgentTables } from './agent-migrate';
import type {
  AgentRegistry, AgentJob, AgentAction, AgentReport,
  AgentStatus, ActionStatus, ProposedAction
} from '../types/agents';

// Run migration on module load (idempotent)
migrateAgentTables();

// --- Registry ---

export function registerAgent(agent: Omit<AgentRegistry, 'last_run_at'>): void {
  db.prepare(`
    INSERT OR REPLACE INTO agent_registry
      (agent_name, description, schedule, allowed_action_types, enabled, last_run_at, config)
    VALUES (?, ?, ?, ?, ?, NULL, ?)
  `).run(
    agent.agent_name,
    agent.description,
    agent.schedule ?? null,
    agent.allowed_action_types,
    agent.enabled,
    agent.config ?? null
  );
}

export function getAgent(name: string): AgentRegistry | undefined {
  return db.prepare('SELECT * FROM agent_registry WHERE agent_name = ?').get(name) as AgentRegistry | undefined;
}

export function listAgents(): AgentRegistry[] {
  return db.prepare('SELECT * FROM agent_registry ORDER BY agent_name').all() as AgentRegistry[];
}

export function setAgentEnabled(name: string, enabled: boolean): void {
  db.prepare('UPDATE agent_registry SET enabled = ? WHERE agent_name = ?').run(enabled ? 1 : 0, name);
}

export function touchAgentLastRun(name: string): void {
  db.prepare('UPDATE agent_registry SET last_run_at = ? WHERE agent_name = ?').run(new Date().toISOString(), name);
}

// --- Jobs ---

export function createJob(agentName: string): AgentJob {
  const job: AgentJob = {
    id: randomUUID(),
    agent_name: agentName,
    status: 'running',
    started_at: new Date().toISOString(),
    completed_at: null,
    summary: null,
  };
  db.prepare(`
    INSERT INTO agent_jobs (id, agent_name, status, started_at, completed_at, summary)
    VALUES (?, ?, ?, ?, NULL, NULL)
  `).run(job.id, job.agent_name, job.status, job.started_at);
  return job;
}

export function updateJobStatus(id: string, status: AgentStatus, summary?: string): void {
  db.prepare(`
    UPDATE agent_jobs SET status = ?, completed_at = ?, summary = ? WHERE id = ?
  `).run(
    status,
    status === 'complete' || status === 'error' ? new Date().toISOString() : null,
    summary ?? null,
    id
  );
}

export function getJob(id: string): AgentJob | undefined {
  return db.prepare('SELECT * FROM agent_jobs WHERE id = ?').get(id) as AgentJob | undefined;
}

export function getJobsByAgent(agentName: string, limit = 10): AgentJob[] {
  return db.prepare(
    'SELECT * FROM agent_jobs WHERE agent_name = ? ORDER BY started_at DESC LIMIT ?'
  ).all(agentName, limit) as AgentJob[];
}

export function getPausedJobs(): AgentJob[] {
  return db.prepare(
    "SELECT * FROM agent_jobs WHERE status = 'paused' ORDER BY started_at ASC"
  ).all() as AgentJob[];
}

// --- Actions ---

export function writeActions(jobId: string, proposed: ProposedAction[]): AgentAction[] {
  const now = new Date().toISOString();
  const actions: AgentAction[] = proposed.map(p => ({
    id: randomUUID(),
    job_id: jobId,
    action_type: p.action_type,
    target_id: p.target_id,
    target_type: p.target_type,
    payload: JSON.stringify(p.payload),
    rationale: p.rationale,
    confidence: p.confidence,
    status: 'pending' as ActionStatus,
    created_at: now,
    reviewed_at: null,
    executed_at: null,
  }));

  const stmt = db.prepare(`
    INSERT INTO agent_actions
      (id, job_id, action_type, target_id, target_type, payload, rationale, confidence, status, created_at, reviewed_at, executed_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NULL, NULL)
  `);

  const insertAll = db.transaction(() => {
    for (const a of actions) {
      stmt.run(a.id, a.job_id, a.action_type, a.target_id, a.target_type, a.payload, a.rationale, a.confidence, a.created_at);
    }
  });
  insertAll();

  return actions;
}

export function getPendingActions(jobId: string): AgentAction[] {
  return db.prepare(
    "SELECT * FROM agent_actions WHERE job_id = ? AND status = 'pending' ORDER BY created_at ASC"
  ).all(jobId) as AgentAction[];
}

export function getAllPendingActions(): AgentAction[] {
  return db.prepare(
    "SELECT * FROM agent_actions WHERE status = 'pending' ORDER BY created_at ASC"
  ).all() as AgentAction[];
}

export function updateActionStatus(id: string, status: ActionStatus): void {
  const now = new Date().toISOString();
  if (status === 'done' || status === 'executing') {
    db.prepare('UPDATE agent_actions SET status = ?, executed_at = ? WHERE id = ?').run(status, now, id);
  } else {
    db.prepare('UPDATE agent_actions SET status = ?, reviewed_at = ? WHERE id = ?').run(status, now, id);
  }
}

export function updateActionPayload(id: string, payload: Record<string, unknown>): void {
  db.prepare('UPDATE agent_actions SET payload = ? WHERE id = ?').run(JSON.stringify(payload), id);
}

export function getAction(id: string): AgentAction | undefined {
  return db.prepare('SELECT * FROM agent_actions WHERE id = ?').get(id) as AgentAction | undefined;
}

// --- Reports ---

export function writeReport(jobId: string, title: string, body: string): AgentReport {
  const report: AgentReport = {
    id: randomUUID(),
    job_id: jobId,
    title,
    body,
    delivered_to: '[]',
    created_at: new Date().toISOString(),
  };
  db.prepare(`
    INSERT INTO agent_reports (id, job_id, title, body, delivered_to, created_at)
    VALUES (?, ?, ?, ?, '[]', ?)
  `).run(report.id, report.job_id, report.title, report.body, report.created_at);
  return report;
}

export function markReportDelivered(id: string, channel: string): void {
  const report = db.prepare('SELECT delivered_to FROM agent_reports WHERE id = ?').get(id) as { delivered_to: string } | undefined;
  if (!report) return;
  const channels: string[] = JSON.parse(report.delivered_to);
  if (!channels.includes(channel)) channels.push(channel);
  db.prepare('UPDATE agent_reports SET delivered_to = ? WHERE id = ?').run(JSON.stringify(channels), id);
}

export function getReports(limit = 20): AgentReport[] {
  return db.prepare(
    'SELECT * FROM agent_reports ORDER BY created_at DESC LIMIT ?'
  ).all(limit) as AgentReport[];
}

export function getReportsByJob(jobId: string): AgentReport[] {
  return db.prepare(
    'SELECT * FROM agent_reports WHERE job_id = ? ORDER BY created_at DESC'
  ).all(jobId) as AgentReport[];
}
```

**Step 2: Write DB helpers test**

Create `src/lib/agent-db.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  const agentDb = await import('./agent-db');

  const TEST_AGENT = 'test-agent-' + Date.now();

  // Test: register and retrieve agent
  {
    agentDb.registerAgent({
      agent_name: TEST_AGENT,
      description: 'Test agent',
      schedule: null,
      allowed_action_types: '["things.update_notes"]',
      enabled: 1,
      config: null,
    });
    const retrieved = agentDb.getAgent(TEST_AGENT);
    assert.ok(retrieved, 'Agent should be retrievable');
    assert.strictEqual(retrieved.agent_name, TEST_AGENT);
    console.log('  ✓ registerAgent / getAgent');
  }

  // Test: create and update job
  {
    const job = agentDb.createJob(TEST_AGENT);
    assert.strictEqual(job.status, 'running');
    agentDb.updateJobStatus(job.id, 'paused', 'Awaiting approval');
    const updated = agentDb.getJob(job.id);
    assert.strictEqual(updated?.status, 'paused');
    console.log('  ✓ createJob / updateJobStatus');

    // Test: write and retrieve actions
    const actions = agentDb.writeActions(job.id, [{
      action_type: 'things.update_notes',
      target_id: 'fake-task-id',
      target_type: 'things_task',
      payload: { notes: 'test note' },
      rationale: 'Test rationale',
      confidence: 0.9,
    }]);
    assert.strictEqual(actions.length, 1);
    assert.strictEqual(actions[0].status, 'pending');
    console.log('  ✓ writeActions');

    // Test: approve action
    agentDb.updateActionStatus(actions[0].id, 'approved');
    const updated2 = agentDb.getAction(actions[0].id);
    assert.strictEqual(updated2?.status, 'approved');
    console.log('  ✓ updateActionStatus (approved)');

    // Test: write report
    const report = agentDb.writeReport(job.id, 'Test Report', '## Summary\nTest content');
    assert.ok(report.id);
    agentDb.markReportDelivered(report.id, 'apple-notes');
    const reports = agentDb.getReportsByJob(job.id);
    assert.strictEqual(reports.length, 1);
    assert.ok(JSON.parse(reports[0].delivered_to).includes('apple-notes'));
    console.log('  ✓ writeReport / markReportDelivered');
  }

  console.log('\nAll agent-db tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 3: Run test**
```bash
npx ts-node src/lib/agent-db.test.ts
```
Expected: 5 checks + `All agent-db tests passed!`

**Step 4: Commit**
```bash
git add src/lib/agent-db.ts src/lib/agent-db.test.ts src/lib/agent-migrate.ts
git commit -m "feat(agents): add agent DB helpers (registry, jobs, actions, reports)"
```

---

## Task 4: Anonymization Layer

**Files:**
- Create: `src/lib/anonymize.ts`
- Create: `scripts/anonymize-debug.ts`

**Step 1: Write `src/lib/anonymize.ts`**

```typescript
import { generate } from './ollama';
import { logger } from './logger';

const anonLogger = logger.child({ module: 'anonymize' });

export interface AnonymizeResult {
  text: string;
  tokenMap: Record<string, string>;   // replacement → original (stored locally only)
}

// Regex pass: structured PII
function regexPass(text: string, tokenMap: Record<string, string>): string {
  let counter = { EMAIL: 0, PHONE: 0, URL: 0, UUID: 0 };

  const patterns: Array<[RegExp, string]> = [
    [/[\w.+-]+@[\w-]+\.[\w.]+/g, 'EMAIL'],
    [/(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}/g, 'PHONE'],
    [/https?:\/\/[^\s]+/g, 'URL'],
    [/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, 'UUID'],
  ];

  let result = text;
  for (const [pattern, label] of patterns) {
    result = result.replace(pattern, (match) => {
      counter[label as keyof typeof counter]++;
      const token = `[${label}_${counter[label as keyof typeof counter]}]`;
      tokenMap[token] = match;
      return token;
    });
  }
  return result;
}

// NER pass: contextual PII via Ollama
async function nerPass(text: string, tokenMap: Record<string, string>): Promise<string> {
  const prompt = `You are a privacy filter. Identify all names of people, places, organizations, and account references in this text. Return ONLY a JSON array of objects: [{"original":"John Smith","label":"PERSON"},{"original":"Acme Corp","label":"ORG"},...]. If none found, return [].

Text:
${text}`;

  try {
    const response = await generate(prompt, { timeoutMs: 30000, temperature: 0 });
    const jsonMatch = response.match(/\[[\s\S]*\]/);
    if (!jsonMatch) return text;

    const entities: Array<{ original: string; label: string }> = JSON.parse(jsonMatch[0]);
    const labelCounts: Record<string, number> = {};
    let result = text;

    for (const entity of entities) {
      if (!entity.original || entity.original.length < 2) continue;
      const label = entity.label || 'ENTITY';
      labelCounts[label] = (labelCounts[label] || 0) + 1;
      const token = `[${label}_${labelCounts[label]}]`;
      if (!Object.values(tokenMap).includes(entity.original)) {
        tokenMap[token] = entity.original;
        result = result.split(entity.original).join(token);
      }
    }
    return result;
  } catch (err) {
    anonLogger.warn({ err }, 'NER pass failed, using regex-only result');
    return text;
  }
}

/**
 * Anonymize text for safe sharing outside this machine.
 * Returns anonymized text + token map (store locally, never share).
 */
export async function anonymize(text: string): Promise<AnonymizeResult> {
  const tokenMap: Record<string, string> = {};
  const afterRegex = regexPass(text, tokenMap);
  const afterNer = await nerPass(afterRegex, tokenMap);

  anonLogger.debug({ replacements: Object.keys(tokenMap).length }, 'Anonymization complete');

  return { text: afterNer, tokenMap };
}
```

**Step 2: Write `scripts/anonymize-debug.ts`**

```typescript
#!/usr/bin/env ts-node
import { anonymize } from '../src/lib/anonymize';

const input = process.argv.slice(2).join(' ') || 'John Smith from Apple emailed john@apple.com about meeting at 555-123-4567';

console.log('\n--- INPUT ---');
console.log(input);

anonymize(input).then(({ text, tokenMap }) => {
  console.log('\n--- ANONYMIZED ---');
  console.log(text);
  console.log('\n--- TOKEN MAP (local only, never share) ---');
  console.log(JSON.stringify(tokenMap, null, 2));
}).catch(err => {
  console.error('Failed:', err);
  process.exit(1);
});
```

**Step 3: Write anonymize test**

Create `src/lib/anonymize.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  // Use a module reset to avoid Ollama calls in tests — test only the regex pass indirectly
  // by checking emails/URLs/UUIDs are replaced
  const { anonymize } = await import('./anonymize');

  // Note: NER pass calls Ollama. We test regex-detectable PII only.
  const input = 'Email me at test@example.com or visit https://example.com (uuid: 550e8400-e29b-41d4-a716-446655440000)';

  try {
    const { text, tokenMap } = await anonymize(input);
    assert.ok(!text.includes('test@example.com'), 'Email should be replaced');
    assert.ok(!text.includes('https://example.com'), 'URL should be replaced');
    assert.ok(!text.includes('550e8400-e29b-41d4-a716-446655440000'), 'UUID should be replaced');
    assert.ok(Object.keys(tokenMap).length >= 3, 'Token map should have at least 3 entries');
    console.log('  ✓ Regex pass replaces email, URL, UUID');
    console.log('  ✓ Token map populated');
    console.log('  Anonymized output:', text);
  } catch (err) {
    // Ollama might not be running — skip gracefully
    if (err instanceof Error && err.message.includes('Ollama')) {
      console.log('  (skipped: Ollama not available)');
    } else {
      throw err;
    }
  }

  console.log('\nAll anonymize tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 4: Run test**
```bash
npx ts-node src/lib/anonymize.test.ts
```
Expected: email/URL/UUID replaced

**Step 5: Commit**
```bash
git add src/lib/anonymize.ts src/lib/anonymize.test.ts scripts/anonymize-debug.ts
git commit -m "feat(agents): add anonymization layer with regex + NER pass"
```

---

## Task 5: Things Task Metadata Enricher Agent

**Files:**
- Create: `src/agents/things-enricher.ts`

This is the first real agent. It reads tasks from a configurable Things project via AppleScript, queries the Selene note archive for related content on each task topic, calls Ollama to propose metadata, writes pending actions, and sets the job to `paused`.

**Step 1: Write `src/agents/things-enricher.ts`**

```typescript
import { execSync } from 'child_process';
import { generate, isAvailable } from '../lib/ollama';
import { searchNotesKeyword } from '../lib/db';
import {
  createJob, updateJobStatus, writeActions, writeReport, getAgent
} from '../lib/agent-db';
import { logger } from '../lib/logger';
import type { ProposedAction } from '../types/agents';

const log = logger.child({ agent: 'things-enricher' });

export const AGENT_NAME = 'things-enricher';

interface ThingsTask {
  id: string;
  name: string;
  notes: string;
  tags: string[];
}

// Read tasks from a Things project via AppleScript
function getThingsTasks(projectName: string): ThingsTask[] {
  const script = `
    tell application "Things3"
      set proj to first project whose name is "${projectName.replace(/"/g, '\\"')}"
      set taskList to to dos of proj
      set result to {}
      repeat with t in taskList
        set taskId to id of t
        set taskName to name of t
        set taskNotes to notes of t
        set taskTags to {}
        repeat with tag in tags of t
          set end of taskTags to name of tag
        end repeat
        set end of result to taskId & "|||" & taskName & "|||" & taskNotes & "|||" & (taskTags as string)
      end repeat
      return result
    end tell
  `;

  try {
    const output = execSync(`osascript -e '${script}'`, { encoding: 'utf-8', timeout: 15000 });
    return output.trim().split(', ').filter(Boolean).map(line => {
      const [id, name, notes, tagsStr] = line.split('|||');
      return {
        id: id?.trim() ?? '',
        name: name?.trim() ?? '',
        notes: notes?.trim() ?? '',
        tags: tagsStr ? tagsStr.split(',').map(t => t.trim()).filter(Boolean) : [],
      };
    }).filter(t => t.id && t.name);
  } catch (err) {
    log.warn({ err }, 'AppleScript failed to read Things tasks');
    return [];
  }
}

// Query Selene note archive for context about a topic
function findRelatedNotes(taskName: string): string {
  const notes = searchNotesKeyword(taskName, 5);
  if (notes.length === 0) return 'No related notes found in Selene archive.';
  return notes.map(n => `- [${n.title}]: ${n.content.slice(0, 200)}...`).join('\n');
}

// Ask Ollama to propose tags and a context note for a task
async function proposeMetadata(task: ThingsTask, relatedNotes: string): Promise<{ tags: string[]; note: string } | null> {
  const prompt = `You are a task metadata assistant. Based on the task title and related notes from the user's knowledge base, suggest:
1. Up to 3 relevant tags (single words or short phrases)
2. A one-sentence context note that would help the user remember why this task matters

Return ONLY valid JSON: {"tags": ["tag1", "tag2"], "note": "Context sentence here."}

Task title: "${task.name}"
Related notes from archive:
${relatedNotes}`;

  try {
    const response = await generate(prompt, { timeoutMs: 60000, temperature: 0.3 });
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;
    return JSON.parse(jsonMatch[0]);
  } catch (err) {
    log.warn({ taskId: task.id, err }, 'Failed to get Ollama proposal');
    return null;
  }
}

export async function runThingsEnricher(): Promise<void> {
  const agentConfig = getAgent(AGENT_NAME);
  if (!agentConfig || !agentConfig.enabled) {
    log.info('Things enricher is disabled or not registered, skipping');
    return;
  }

  const config = agentConfig.config ? JSON.parse(agentConfig.config) as { project: string } : null;
  if (!config?.project) {
    log.error('Agent config missing "project" field — update agent_registry.config');
    return;
  }

  if (!(await isAvailable())) {
    log.error('Ollama not available, skipping');
    return;
  }

  const job = createJob(AGENT_NAME);
  log.info({ jobId: job.id, project: config.project }, 'Starting Things enricher run');

  const tasks = getThingsTasks(config.project);
  log.info({ taskCount: tasks.length }, 'Fetched tasks from Things');

  if (tasks.length === 0) {
    updateJobStatus(job.id, 'complete', 'No tasks found in project');
    return;
  }

  const proposed: ProposedAction[] = [];
  const enrichedTasks: string[] = [];

  for (const task of tasks) {
    // Skip tasks that already have both notes and tags
    if (task.notes.trim() && task.tags.length >= 2) {
      log.debug({ taskId: task.id }, 'Task already has metadata, skipping');
      continue;
    }

    const relatedNotes = findRelatedNotes(task.name);
    const suggestion = await proposeMetadata(task, relatedNotes);
    if (!suggestion) continue;

    if (!task.notes.trim() && suggestion.note) {
      proposed.push({
        action_type: 'things.update_notes',
        target_id: task.id,
        target_type: 'things_task',
        payload: { notes: suggestion.note, taskName: task.name },
        rationale: `Task has no notes. Suggested context based on ${relatedNotes.includes('No related') ? 'task title' : 'related Selene notes'}.`,
        confidence: relatedNotes.includes('No related') ? 0.6 : 0.85,
      });
    }

    if (task.tags.length === 0 && suggestion.tags.length > 0) {
      for (const tag of suggestion.tags) {
        proposed.push({
          action_type: 'things.add_tag',
          target_id: task.id,
          target_type: 'things_task',
          payload: { tag, taskName: task.name },
          rationale: `Task has no tags. "${tag}" suggested based on task content and related notes.`,
          confidence: 0.75,
        });
      }
    }

    enrichedTasks.push(`- **${task.name}**: ${suggestion.tags.length} tag(s) proposed, note: "${suggestion.note?.slice(0, 80)}..."`);
  }

  if (proposed.length === 0) {
    updateJobStatus(job.id, 'complete', 'All tasks already have sufficient metadata');
    return;
  }

  writeActions(job.id, proposed);

  const reportBody = `## Things Task Metadata Enricher Report

**Project:** ${config.project}
**Tasks scanned:** ${tasks.length}
**Actions proposed:** ${proposed.length}
**Run time:** ${new Date().toISOString()}

### Proposed Enrichments

${enrichedTasks.join('\n')}

---
*Review and approve in the Selene dashboard at http://localhost:5678/dashboard*`;

  writeReport(job.id, `Things Enricher: ${proposed.length} actions pending`, reportBody);
  updateJobStatus(job.id, 'paused', `${proposed.length} actions pending approval`);

  log.info({ jobId: job.id, proposed: proposed.length }, 'Things enricher paused, awaiting approval');
}
```

**Step 2: Write Things enricher test**

Create `src/agents/things-enricher.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  const { AGENT_NAME } = await import('./things-enricher');
  const agentDb = await import('../lib/agent-db');

  // Register test agent
  agentDb.registerAgent({
    agent_name: AGENT_NAME,
    description: 'Test: Things Task Metadata Enricher',
    schedule: null,
    allowed_action_types: JSON.stringify(['things.update_notes', 'things.add_tag']),
    enabled: 0, // disabled so runThingsEnricher returns early
    config: JSON.stringify({ project: 'TestProject' }),
  });

  const agent = agentDb.getAgent(AGENT_NAME);
  assert.ok(agent, 'Agent should be registered');
  assert.strictEqual(agent.agent_name, AGENT_NAME);
  console.log('  ✓ Agent registers correctly');

  // Verify action vocabulary is correct
  const allowed = JSON.parse(agent.allowed_action_types) as string[];
  assert.ok(allowed.includes('things.update_notes'));
  assert.ok(allowed.includes('things.add_tag'));
  console.log('  ✓ Action vocabulary is correct');

  console.log('\nAll things-enricher tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 3: Run test**
```bash
npx ts-node src/agents/things-enricher.test.ts
```
Expected: `All things-enricher tests passed!`

**Step 4: Commit**
```bash
git add src/agents/things-enricher.ts src/agents/things-enricher.test.ts
git commit -m "feat(agents): add Things Task Metadata Enricher agent"
```

---

## Task 6: Action Executors (Process Code)

**Files:**
- Create: `src/agents/executors.ts`

Deterministic TypeScript functions, one per `action_type`. Called only after approval. The LLM never executes directly.

**Step 1: Write `src/agents/executors.ts`**

```typescript
import { execSync } from 'child_process';
import { logger } from '../lib/logger';
import type { AgentAction, ActionType } from '../types/agents';

const log = logger.child({ module: 'executors' });

// Execute a single approved action. Throws on failure.
export async function executeAction(action: AgentAction): Promise<void> {
  const payload = JSON.parse(action.payload) as Record<string, unknown>;

  switch (action.action_type as ActionType) {
    case 'things.update_notes':
      await executeThingsUpdateNotes(action.target_id, payload);
      break;
    case 'things.add_tag':
      await executeThingsAddTag(action.target_id, payload);
      break;
    default:
      throw new Error(`Unknown action_type: ${action.action_type}`);
  }
}

function executeThingsUpdateNotes(taskId: string, payload: Record<string, unknown>): void {
  const notes = String(payload.notes ?? '');
  const script = `
    tell application "Things3"
      set theTask to to do id "${taskId.replace(/"/g, '\\"')}"
      set notes of theTask to "${notes.replace(/"/g, '\\"').replace(/\n/g, '\\n')}"
    end tell
  `;
  try {
    execSync(`osascript -e '${script}'`, { timeout: 10000 });
    log.info({ taskId, notes: notes.slice(0, 50) }, 'Updated Things task notes');
  } catch (err) {
    throw new Error(`Failed to update Things task notes: ${(err as Error).message}`);
  }
}

function executeThingsAddTag(taskId: string, payload: Record<string, unknown>): void {
  const tag = String(payload.tag ?? '');
  if (!tag) throw new Error('tag is required in payload');

  const script = `
    tell application "Things3"
      set theTask to to do id "${taskId.replace(/"/g, '\\"')}"
      set tagName to "${tag.replace(/"/g, '\\"')}"
      -- Create tag if it doesn't exist
      if not (exists tag tagName) then
        make new tag with properties {name: tagName}
      end if
      set tags of theTask to tags of theTask & {tag tagName}
    end tell
  `;
  try {
    execSync(`osascript -e '${script}'`, { timeout: 10000 });
    log.info({ taskId, tag }, 'Added tag to Things task');
  } catch (err) {
    throw new Error(`Failed to add tag to Things task: ${(err as Error).message}`);
  }
}
```

**Step 2: Write executor test**

Create `src/agents/executors.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  const { executeAction } = await import('./executors');

  // Test: unknown action_type throws
  try {
    await executeAction({
      id: 'test',
      job_id: 'test-job',
      action_type: 'unknown.action' as any,
      target_id: 'fake-id',
      target_type: 'things_task',
      payload: '{}',
      rationale: 'test',
      confidence: 1.0,
      status: 'approved',
      created_at: new Date().toISOString(),
      reviewed_at: null,
      executed_at: null,
    });
    assert.fail('Should have thrown for unknown action_type');
  } catch (err) {
    assert.ok((err as Error).message.includes('Unknown action_type'));
    console.log('  ✓ Unknown action_type throws correctly');
  }

  console.log('\nAll executor tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 3: Run test**
```bash
npx ts-node src/agents/executors.test.ts
```
Expected: `All executor tests passed!`

**Step 4: Commit**
```bash
git add src/agents/executors.ts src/agents/executors.test.ts
git commit -m "feat(agents): add deterministic action executors"
```

---

## Task 7: Report Delivery (Apple Notes + Obsidian)

**Files:**
- Create: `src/lib/agent-delivery.ts`

Reuses patterns from `send-digest.ts` (Apple Notes) and `export-obsidian.ts` (file write).

**Step 1: Write `src/lib/agent-delivery.ts`**

```typescript
import { execSync } from 'child_process';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { config } from './config';
import { logger } from './logger';
import { markReportDelivered } from './agent-db';
import type { AgentReport } from '../types/agents';

const log = logger.child({ module: 'agent-delivery' });

// Deliver report to Apple Notes (one pinned note per agent, appended each run)
export function deliverToAppleNotes(report: AgentReport, agentName: string): void {
  const noteTitle = `Selene: ${agentName}`;
  const body = `${new Date().toLocaleString()}\n\n${report.body}`;
  const escapedTitle = noteTitle.replace(/"/g, '\\"');
  const escapedBody = body.replace(/"/g, '\\"').replace(/\n/g, '\\n');

  const script = `
    tell application "Notes"
      set targetNote to missing value
      repeat with n in notes of default account
        if name of n is "${escapedTitle}" then
          set targetNote to n
          exit repeat
        end if
      end repeat
      if targetNote is missing value then
        set targetNote to make new note at default account with properties {name:"${escapedTitle}", body:"${escapedBody}"}
      else
        set body of targetNote to body of targetNote & "\\n\\n---\\n\\n${escapedBody}"
      end if
    end tell
  `;

  try {
    execSync(`osascript -e '${script}'`, { timeout: 15000 });
    markReportDelivered(report.id, 'apple-notes');
    log.info({ reportId: report.id, agent: agentName }, 'Report delivered to Apple Notes');
  } catch (err) {
    log.warn({ err, reportId: report.id }, 'Apple Notes delivery failed');
  }
}

// Deliver report to Obsidian vault (one file per run)
export function deliverToObsidian(report: AgentReport, agentName: string): void {
  if (!config.vaultPath) {
    log.warn('OBSIDIAN_VAULT_PATH not set, skipping Obsidian delivery');
    return;
  }

  const date = new Date().toISOString().slice(0, 10);
  const dir = join(config.vaultPath, 'agent-reports');
  const filename = `${date}-${agentName}.md`;
  const filepath = join(dir, filename);

  try {
    mkdirSync(dir, { recursive: true });
    const content = `---\nagent: ${agentName}\ndate: ${date}\n---\n\n${report.body}`;
    writeFileSync(filepath, content, 'utf-8');
    markReportDelivered(report.id, 'obsidian');
    log.info({ reportId: report.id, filepath }, 'Report delivered to Obsidian');
  } catch (err) {
    log.warn({ err, reportId: report.id }, 'Obsidian delivery failed');
  }
}
```

**Step 2: Commit (no isolated test — delivery requires Apple Notes/Obsidian)**
```bash
git add src/lib/agent-delivery.ts
git commit -m "feat(agents): add report delivery to Apple Notes and Obsidian"
```

---

## Task 8: Fastify API Routes for Agent Control

**Files:**
- Create: `src/routes/agents.ts`
- Modify: `src/server.ts`

**Step 1: Write `src/routes/agents.ts`**

```typescript
import type { FastifyInstance } from 'fastify';
import {
  listAgents, getJobsByAgent, getAllPendingActions,
  updateActionStatus, updateActionPayload, getAction, getReports, getPausedJobs
} from '../lib/agent-db';
import { executeAction } from '../agents/executors';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'routes/agents' });

export async function agentRoutes(server: FastifyInstance): Promise<void> {
  // GET /agents/status — all agent status + pending action count
  server.get('/agents/status', async () => {
    const agents = listAgents();
    const pendingActions = getAllPendingActions();
    const pausedJobs = getPausedJobs();
    return {
      agents,
      pendingActionCount: pendingActions.length,
      pausedJobCount: pausedJobs.length,
    };
  });

  // GET /agents/:name/jobs — job history for an agent
  server.get<{ Params: { name: string } }>('/agents/:name/jobs', async (req) => {
    return { jobs: getJobsByAgent(req.params.name) };
  });

  // GET /agent-actions/pending — all pending actions
  server.get('/agent-actions/pending', async () => {
    return { actions: getAllPendingActions() };
  });

  // POST /agent-actions/:id/approve — approve and execute.
  // Detects HTML form submissions (content-type: application/x-www-form-urlencoded)
  // and redirects back to the dashboard. API callers get JSON.
  server.post<{ Params: { id: string } }>('/agent-actions/:id/approve', async (req, reply) => {
    const isFormPost = req.headers['content-type']?.includes('application/x-www-form-urlencoded');
    const action = getAction(req.params.id);
    if (!action) {
      if (isFormPost) return reply.redirect('/dashboard/approvals');
      reply.status(404);
      return { error: 'Action not found' };
    }
    if (action.status !== 'pending') {
      if (isFormPost) return reply.redirect('/dashboard/approvals');
      reply.status(400);
      return { error: `Action status is "${action.status}", expected "pending"` };
    }

    updateActionStatus(action.id, 'executing');
    try {
      await executeAction(action);
      updateActionStatus(action.id, 'done');
      log.info({ actionId: action.id, type: action.action_type }, 'Action executed');
      if (isFormPost) return reply.redirect('/dashboard/approvals');
      return { success: true, actionId: action.id };
    } catch (err) {
      updateActionStatus(action.id, 'rejected');
      log.error({ actionId: action.id, err }, 'Action execution failed');
      if (isFormPost) return reply.redirect('/dashboard/approvals');
      reply.status(500);
      return { error: (err as Error).message };
    }
  });

  // POST /agent-actions/:id/reject — same dual-mode pattern as approve.
  server.post<{ Params: { id: string } }>('/agent-actions/:id/reject', async (req, reply) => {
    const isFormPost = req.headers['content-type']?.includes('application/x-www-form-urlencoded');
    const action = getAction(req.params.id);
    if (!action) {
      if (isFormPost) return reply.redirect('/dashboard/approvals');
      reply.status(404);
      return { error: 'Action not found' };
    }
    updateActionStatus(action.id, 'rejected');
    if (isFormPost) return reply.redirect('/dashboard/approvals');
    return { success: true };
  });

  // PUT /agent-actions/:id — edit payload then approve
  server.put<{
    Params: { id: string };
    Body: { payload: Record<string, unknown> };
  }>('/agent-actions/:id', async (req, reply) => {
    const action = getAction(req.params.id);
    if (!action) { reply.status(404); return { error: 'Action not found' }; }
    if (action.status !== 'pending') {
      reply.status(400);
      return { error: `Cannot edit action with status "${action.status}"` };
    }
    updateActionPayload(action.id, req.body.payload);
    updateActionStatus(action.id, 'executing');
    try {
      const updated = getAction(action.id)!;
      await executeAction(updated);
      updateActionStatus(action.id, 'done');
      return { success: true };
    } catch (err) {
      updateActionStatus(action.id, 'rejected');
      reply.status(500);
      return { error: (err as Error).message };
    }
  });

  // GET /agent-reports — all reports
  server.get('/agent-reports', async () => {
    return { reports: getReports(50) };
  });
}
```

**Step 2: Register routes in `src/server.ts`**

Add after the existing route registrations:
```typescript
import { agentRoutes } from './routes/agents';

// ... existing code ...

// Agent control routes
server.register(agentRoutes);
```

**Step 3: Test routes manually**
```bash
# Start server
npx ts-node src/server.ts &
SERVER_PID=$!
sleep 2

# Test status endpoint
curl -s http://localhost:5678/agents/status | python3 -m json.tool

# Test pending actions
curl -s http://localhost:5678/agent-actions/pending | python3 -m json.tool

kill $SERVER_PID
```
Expected: JSON with `agents`, `pendingActionCount`, `pausedJobCount`

**Step 4: Commit**
```bash
git add src/routes/agents.ts src/server.ts
git commit -m "feat(agents): add Fastify API routes for agent control"
```

---

## Task 9: Web Dashboard (Server-Rendered HTML)

**Files:**
- Create: `src/dashboard/index.ts`
- Modify: `src/server.ts`

The dashboard is pure server-rendered HTML — no build step. Fastify sends HTML strings. Minimal inline CSS.

**Step 1: Write `src/dashboard/index.ts`**

```typescript
import type { FastifyInstance } from 'fastify';
import {
  listAgents, getAllPendingActions, getReports, getPausedJobs,
  getJobsByAgent, getAction
} from '../lib/agent-db';

// Minimal shared styles
const CSS = `
  body { font-family: -apple-system, sans-serif; margin: 0; background: #f5f5f5; color: #1a1a1a; }
  nav { background: #1a1a1a; padding: 12px 24px; display: flex; gap: 24px; }
  nav a { color: #ccc; text-decoration: none; font-size: 14px; }
  nav a:hover { color: white; }
  nav .badge { background: #e53e3e; color: white; border-radius: 10px; padding: 1px 7px; font-size: 11px; margin-left: 4px; }
  main { max-width: 900px; margin: 24px auto; padding: 0 24px; }
  h1 { font-size: 22px; margin-bottom: 16px; }
  h2 { font-size: 16px; margin: 24px 0 8px; color: #555; text-transform: uppercase; letter-spacing: 0.05em; }
  .card { background: white; border-radius: 8px; padding: 16px; margin-bottom: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  .badge-status { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; font-weight: 500; }
  .status-running { background: #d1fae5; color: #065f46; }
  .status-paused { background: #fef3c7; color: #92400e; }
  .status-idle { background: #e5e7eb; color: #374151; }
  .status-error { background: #fee2e2; color: #991b1b; }
  .confidence { font-size: 12px; color: #888; }
  form { display: inline; }
  button { padding: 6px 14px; border-radius: 4px; border: none; cursor: pointer; font-size: 13px; margin-right: 6px; }
  .btn-approve { background: #059669; color: white; }
  .btn-reject { background: #dc2626; color: white; }
  .rationale { font-size: 13px; color: #555; margin-top: 6px; font-style: italic; }
  .report-body { white-space: pre-wrap; font-size: 13px; font-family: monospace; background: #f9f9f9; padding: 12px; border-radius: 4px; margin-top: 8px; }
  .empty { color: #888; font-style: italic; }
`;

function layout(title: string, body: string, pendingCount: number): string {
  const badge = pendingCount > 0 ? `<span class="badge">${pendingCount}</span>` : '';
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>${title} — Selene</title><style>${CSS}</style></head>
<body>
<nav>
  <a href="/dashboard">Home</a>
  <a href="/dashboard/approvals">Approvals${badge}</a>
  <a href="/dashboard/reports">Reports</a>
  <a href="/dashboard/agents">Agents</a>
</nav>
<main>${body}</main>
</body>
</html>`;
}

export async function dashboardRoutes(server: FastifyInstance): Promise<void> {
  // Home — agent status cards + activity feed
  server.get('/dashboard', async (_req, reply) => {
    const agents = listAgents();
    const pending = getAllPendingActions();
    const paused = getPausedJobs();

    const agentCards = agents.length === 0
      ? '<p class="empty">No agents registered.</p>'
      : agents.map(a => {
          const jobs = getJobsByAgent(a.agent_name, 1);
          const latestJob = jobs[0];
          const status = latestJob?.status ?? 'idle';
          return `<div class="card">
            <strong>${a.agent_name}</strong>
            <span class="badge-status status-${status}" style="margin-left:8px">${status}</span>
            <div style="font-size:13px;color:#666;margin-top:4px">${a.description}</div>
            ${a.last_run_at ? `<div style="font-size:12px;color:#aaa;margin-top:2px">Last run: ${new Date(a.last_run_at).toLocaleString()}</div>` : ''}
          </div>`;
        }).join('');

    const body = `
      <h1>Selene Agent Dashboard</h1>
      ${pending.length > 0 ? `<div class="card" style="background:#fef3c7;border-left:4px solid #f59e0b">
        <strong>${pending.length} action(s) pending approval</strong>
        — <a href="/dashboard/approvals">Review now</a>
      </div>` : ''}
      <h2>Agents</h2>${agentCards}
      <h2>Paused Jobs</h2>
      ${paused.length === 0
        ? '<p class="empty">No paused jobs.</p>'
        : paused.map(j => `<div class="card"><strong>${j.agent_name}</strong> — paused since ${new Date(j.started_at).toLocaleString()}<br><span class="rationale">${j.summary ?? ''}</span></div>`).join('')}
    `;
    reply.type('text/html').send(layout('Home', body, pending.length));
  });

  // Approvals — grouped by agent
  server.get('/dashboard/approvals', async (_req, reply) => {
    const pending = getAllPendingActions();
    const grouped: Record<string, typeof pending> = {};
    for (const a of pending) {
      if (!grouped[a.job_id]) grouped[a.job_id] = [];
      grouped[a.job_id].push(a);
    }

    const actionCards = Object.entries(grouped).map(([jobId, actions]) => {
      const rows = actions.map(a => {
        const payload = JSON.parse(a.payload) as Record<string, unknown>;
        return `<div style="border-top:1px solid #eee;padding-top:10px;margin-top:10px">
          <strong>${a.action_type}</strong>
          <span class="confidence">— confidence: ${(a.confidence * 100).toFixed(0)}%</span>
          <br><code style="font-size:12px">${JSON.stringify(payload)}</code>
          <div class="rationale">${a.rationale}</div>
          <div style="margin-top:8px">
            <form action="/agent-actions/${a.id}/approve" method="post">
              <button class="btn-approve" type="submit">Approve</button>
            </form>
            <form action="/agent-actions/${a.id}/reject" method="post">
              <button class="btn-reject" type="submit">Reject</button>
            </form>
          </div>
        </div>`;
      }).join('');
      return `<div class="card"><strong>Job ${jobId.slice(0, 8)}…</strong>${rows}</div>`;
    }).join('');

    const body = `
      <h1>Approval Queue</h1>
      ${pending.length === 0 ? '<p class="empty">No pending actions. You\'re all caught up!</p>' : actionCards}
    `;
    reply.type('text/html').send(layout('Approvals', body, pending.length));
  });

  // NOTE: approve/reject form POSTs are handled by the routes in src/routes/agents.ts.
  // Those routes detect application/x-www-form-urlencoded and redirect back here.
  // Do NOT register duplicate /agent-actions/:id/approve or /agent-actions/:id/reject here.

  // Reports
  server.get('/dashboard/reports', async (_req, reply) => {
    const reports = getReports(50);
    const pending = getAllPendingActions();
    const cards = reports.length === 0
      ? '<p class="empty">No reports yet.</p>'
      : reports.map(r => `<div class="card">
          <strong>${r.title}</strong>
          <div style="font-size:12px;color:#aaa">${new Date(r.created_at).toLocaleString()}</div>
          <div class="report-body">${r.body}</div>
        </div>`).join('');
    reply.type('text/html').send(layout('Reports', `<h1>Agent Reports</h1>${cards}`, pending.length));
  });

  // Agent Manager view
  server.get('/dashboard/agents', async (_req, reply) => {
    const agents = listAgents();
    const pending = getAllPendingActions();
    const cards = agents.length === 0
      ? '<p class="empty">No agents registered.</p>'
      : agents.map(a => {
          const allowed = JSON.parse(a.allowed_action_types) as string[];
          return `<div class="card">
            <strong>${a.agent_name}</strong>
            <span class="badge-status ${a.enabled ? 'status-running' : 'status-idle'}" style="margin-left:8px">${a.enabled ? 'enabled' : 'disabled'}</span>
            <div style="font-size:13px;color:#666;margin-top:4px">${a.description}</div>
            <div style="font-size:12px;margin-top:6px"><strong>Actions:</strong> ${allowed.join(', ')}</div>
            ${a.schedule ? `<div style="font-size:12px"><strong>Schedule:</strong> ${a.schedule}</div>` : ''}
            ${a.config ? `<div style="font-size:12px"><strong>Config:</strong> <code>${a.config}</code></div>` : ''}
          </div>`;
        }).join('');
    reply.type('text/html').send(layout('Agents', `<h1>Agent Manager</h1>${cards}`, pending.length));
  });
}
```

**Step 2: Register dashboard in `src/server.ts`**

Add after existing route registrations:
```typescript
import { dashboardRoutes } from './dashboard/index';

// ... existing code ...

server.register(dashboardRoutes);
```

**Step 3: Test dashboard manually**
```bash
# Start server
npx ts-node src/server.ts &
SERVER_PID=$!
sleep 2

# Verify dashboard responds
curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/dashboard
# Expected: 200

curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/dashboard/approvals
# Expected: 200

kill $SERVER_PID
```

**Step 4: Commit**
```bash
git add src/dashboard/index.ts src/server.ts
git commit -m "feat(agents): add server-rendered web dashboard at /dashboard"
```

---

## Task 10: Agent Manager Service

**Files:**
- Create: `src/workflows/agent-manager.ts`
- Create: `launchd/com.selene.agent-manager.plist`

The agent manager registers all known agents on startup, checks for stuck jobs, and escalates stale approvals via macOS notification.

**Step 1: Write `src/workflows/agent-manager.ts`**

```typescript
import { execSync } from 'child_process';
import {
  registerAgent, listAgents, getPausedJobs, touchAgentLastRun
} from '../lib/agent-db';
import { runThingsEnricher, AGENT_NAME as THINGS_ENRICHER } from '../agents/things-enricher';
import { deliverToAppleNotes, deliverToObsidian } from '../lib/agent-delivery';
import { getReportsByJob } from '../lib/agent-db';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'agent-manager' });

const ESCALATION_THRESHOLD_MS = 4 * 60 * 60 * 1000; // 4 hours

// Register all known agents with their config
function seedRegistry(): void {
  registerAgent({
    agent_name: THINGS_ENRICHER,
    description: 'Enriches Things tasks with tags and context notes from the Selene archive',
    schedule: '0 9 * * *', // 9am daily
    allowed_action_types: JSON.stringify(['things.update_notes', 'things.add_tag']),
    enabled: 1,
    config: JSON.stringify({ project: 'Snack City' }),
  });
  log.info('Agent registry seeded');
}

// Deliver pending reports that haven't been delivered yet
async function deliverPendingReports(): Promise<void> {
  const jobs = getPausedJobs();
  for (const job of jobs) {
    const reports = getReportsByJob(job.id);
    for (const report of reports) {
      const delivered: string[] = JSON.parse(report.delivered_to);
      if (!delivered.includes('apple-notes')) {
        deliverToAppleNotes(report, job.agent_name);
      }
      if (!delivered.includes('obsidian')) {
        deliverToObsidian(report, job.agent_name);
      }
    }
  }
}

// Send macOS notification for stale paused jobs
function escalateStaleApprovals(): void {
  const paused = getPausedJobs();
  const now = Date.now();
  for (const job of paused) {
    const age = now - new Date(job.started_at).getTime();
    if (age > ESCALATION_THRESHOLD_MS) {
      const msg = `${job.agent_name} has ${job.summary ?? 'pending actions'} — review at localhost:5678/dashboard`;
      try {
        execSync(`osascript -e 'display notification "${msg.replace(/"/g, '\\"')}" with title "Selene Agent"'`);
        log.info({ jobId: job.id }, 'Sent escalation notification');
      } catch {
        log.warn({ jobId: job.id }, 'Failed to send notification');
      }
    }
  }
}

// Run a named agent by calling its runner function
async function runAgent(name: string): Promise<void> {
  switch (name) {
    case THINGS_ENRICHER:
      await runThingsEnricher();
      touchAgentLastRun(name);
      break;
    default:
      log.warn({ name }, 'Unknown agent name');
  }
}

async function main(): Promise<void> {
  log.info('Agent manager starting');
  seedRegistry();

  // On startup: deliver any un-delivered reports and escalate stale approvals
  await deliverPendingReports();
  escalateStaleApprovals();

  // Run enabled agents (launchd calls this on schedule, not a loop)
  const agents = listAgents().filter(a => a.enabled === 1);
  for (const agent of agents) {
    log.info({ agent: agent.agent_name }, 'Running agent');
    await runAgent(agent.agent_name);
  }

  log.info('Agent manager run complete');
}

main().catch(err => {
  log.error({ err }, 'Agent manager failed');
  process.exit(1);
});
```

**Step 2: Write `launchd/com.selene.agent-manager.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.selene.agent-manager</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/npx</string>
    <string>ts-node</string>
    <string>/Users/chaseeasterling/selene/src/workflows/agent-manager.ts</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict>
      <key>Hour</key>
      <integer>9</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
    <dict>
      <key>Hour</key>
      <integer>18</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
  </array>
  <key>StandardOutPath</key>
  <string>/Users/chaseeasterling/selene/logs/agent-manager.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/chaseeasterling/selene/logs/agent-manager.err.log</string>
  <key>WorkingDirectory</key>
  <string>/Users/chaseeasterling/selene</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
```

**Step 3: Update `scripts/install-launchd.sh` to include the new agent**

Open `scripts/install-launchd.sh` and add `com.selene.agent-manager` to the list of agents being installed.

**Step 4: Commit**
```bash
git add src/workflows/agent-manager.ts launchd/com.selene.agent-manager.plist scripts/install-launchd.sh
git commit -m "feat(agents): add agent manager service and launchd schedule"
```

---

## Task 11: Wire Up `src/lib/index.ts` Exports + End-to-End Test

**Files:**
- Modify: `src/lib/index.ts` (if it exists)
- Create: `src/agents/e2e.test.ts`

**Step 1: Add agent-db and anonymize to lib exports (if `src/lib/index.ts` exists)**
```typescript
export * from './agent-db';
export * from './agent-migrate';
export * from './anonymize';
```

**Step 2: Write end-to-end smoke test**

Create `src/agents/e2e.test.ts`:
```typescript
import assert from 'assert';

async function runTests() {
  // Test: full pipeline without Things (mocked task)
  const agentDb = await import('../lib/agent-db');
  const { AGENT_NAME } = await import('./things-enricher');

  // Register agent if not already
  agentDb.registerAgent({
    agent_name: AGENT_NAME,
    description: 'E2E test agent',
    schedule: null,
    allowed_action_types: JSON.stringify(['things.update_notes', 'things.add_tag']),
    enabled: 1,
    config: JSON.stringify({ project: 'TestProject' }),
  });

  // Simulate a job lifecycle
  const job = agentDb.createJob(AGENT_NAME);
  assert.strictEqual(job.status, 'running');

  const actions = agentDb.writeActions(job.id, [{
    action_type: 'things.update_notes',
    target_id: 'fake-task-e2e',
    target_type: 'things_task',
    payload: { notes: 'E2E test context note', taskName: 'Test Task' },
    rationale: 'E2E test',
    confidence: 0.95,
  }]);

  agentDb.writeReport(job.id, 'E2E Test Report', '## E2E\nTest content');
  agentDb.updateJobStatus(job.id, 'paused', '1 action pending approval');

  // Verify paused job appears
  const paused = agentDb.getPausedJobs();
  assert.ok(paused.find(j => j.id === job.id), 'Job should appear in paused list');
  console.log('  ✓ Job lifecycle: running → paused');

  // Verify action appears in pending
  const pending = agentDb.getAllPendingActions();
  const ourAction = pending.find(a => a.job_id === job.id);
  assert.ok(ourAction, 'Action should appear in pending list');
  console.log('  ✓ Action appears in pending queue');

  // Simulate rejection (safe — no AppleScript)
  agentDb.updateActionStatus(actions[0].id, 'rejected');
  const updated = agentDb.getAction(actions[0].id);
  assert.strictEqual(updated?.status, 'rejected');
  console.log('  ✓ Action can be rejected');

  // Cleanup
  agentDb.updateJobStatus(job.id, 'complete', 'E2E test complete');
  console.log('\nAll E2E smoke tests passed!');
}

runTests().catch((err) => {
  console.error('E2E tests failed:', err);
  process.exit(1);
});
```

**Step 3: Run E2E test**
```bash
npx ts-node src/agents/e2e.test.ts
```
Expected: `All E2E smoke tests passed!`

**Step 4: Run all tests in sequence**
```bash
npx ts-node src/types/agents.test.ts && \
npx ts-node src/lib/agent-migrate.test.ts && \
npx ts-node src/lib/agent-db.test.ts && \
npx ts-node src/lib/anonymize.test.ts && \
npx ts-node src/agents/things-enricher.test.ts && \
npx ts-node src/agents/executors.test.ts && \
npx ts-node src/agents/e2e.test.ts
```
Expected: all pass

**Step 5: Update docs/plans/INDEX.md** — move design doc from "Ready" to "In Progress", add branch reference.

**Step 6: Final commit**
```bash
git add -A
git commit -m "feat(agents): complete agent layer v1 — manager, dashboard, Things enricher"
```

---

## Acceptance Criteria Checklist

- [ ] `src/lib/anonymize.ts` — regex + Ollama NER pass, token map
- [ ] `scripts/anonymize-debug.ts` — debug script
- [ ] 4 SQLite tables in `data/selene.db` — agent_registry, agent_jobs, agent_actions, agent_reports
- [ ] Agent manager via `npx ts-node src/workflows/agent-manager.ts`
- [ ] Web dashboard at `http://localhost:5678/dashboard` — 4 views accessible
- [ ] Report delivery to Apple Notes + Obsidian
- [ ] Things enricher reads project tasks, calls Ollama, writes pending actions
- [ ] Full approval loop: `pending → approved → executed → done` via AppleScript
- [ ] Agent pauses when awaiting approval, resumes after

---

## File Map (All New Files)

```
src/
  types/
    agents.ts           # TypeScript interfaces for all agent concepts
  lib/
    agent-migrate.ts    # SQLite migration (4 tables)
    agent-db.ts         # CRUD helpers for agent tables
    agent-delivery.ts   # Apple Notes + Obsidian delivery
    anonymize.ts        # Two-pass anonymization (regex + NER)
  agents/
    things-enricher.ts  # First agent: Things task metadata
    executors.ts        # Deterministic action executors
  routes/
    agents.ts           # Fastify routes for agent API
  dashboard/
    index.ts            # Server-rendered HTML dashboard
  workflows/
    agent-manager.ts    # Orchestrator service

scripts/
  anonymize-debug.ts    # Debug anonymization on a text input

launchd/
  com.selene.agent-manager.plist  # Runs at 9am + 6pm daily
```
