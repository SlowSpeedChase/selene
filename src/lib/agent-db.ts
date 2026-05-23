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
