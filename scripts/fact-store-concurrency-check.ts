#!/usr/bin/env npx ts-node
/**
 * fact-store-concurrency-check — the acceptance test for WAL + busy_timeout ACROSS the ATTACH.
 *
 * The fact-store split makes the pipeline read `raw_notes` (a TEMP VIEW over
 * facts.captured_notes LEFT JOIN note_state) while the webhook/ingest WRITES facts into
 * facts.captured_notes — through a SEPARATE connection, often a separate process. Both
 * connections go through `openSeleneConnection`, which applies `journal_mode = WAL` +
 * `busy_timeout = 30000` to the main file AND to the attached facts file. If that wiring
 * is correct, a writer hammering facts.captured_notes and a reader repeatedly scanning the
 * view must NEVER see SQLITE_BUSY (they wait for the lock instead).
 *
 * Real OS-level concurrency: this script spawns ITSELF as a separate WRITER child process
 * (its own connection) and, in the parent, runs the READER loop concurrently for the same
 * window. Each role counts its own SQLITE_BUSY and emits a one-line JSON result; the parent
 * aggregates and exits non-zero if the total is > 0 (or if either side never ran an op).
 *
 * The reader replicates getPendingNotes' exact SQL inline (rather than importing the db.ts
 * singleton, which would open a third connection + run the env guard) so the harness uses
 * ONLY the production read/write wiring via openSeleneConnection.
 *
 * Strictly /tmp-isolated: reads SELENE_DB_PATH / SELENE_FACTS_DB_PATH from the env (the Task 10
 * harness points them at /tmp) and refuses to run against anything not under /tmp.
 */
import { spawn } from 'child_process';
import { createHash } from 'crypto';
import { openSeleneConnection, assertTmpIsolated } from '../src/lib/open-selene-connection';

const DB_PATH = process.env.SELENE_DB_PATH || '';
const FACTS_PATH = process.env.SELENE_FACTS_DB_PATH || '';
const DURATION_MS = parseInt(process.env.T10_CONCURRENCY_MS || '4000', 10);

interface RoleResult {
  role: 'reader' | 'writer';
  ops: number;
  busy: number;
}

/** Is this better-sqlite3 error a SQLITE_BUSY / lock-contention error? */
function isBusy(err: unknown): boolean {
  const code = (err as { code?: string } | undefined)?.code ?? '';
  const msg = err instanceof Error ? err.message : String(err);
  return (
    code === 'SQLITE_BUSY' ||
    code === 'SQLITE_BUSY_SNAPSHOT' ||
    /database is locked|SQLITE_BUSY/i.test(msg)
  );
}

/**
 * WRITER role: open the two-file DB read-write (real pragmas + ATTACH) and INSERT into
 * facts.captured_notes as fast as possible for the window. Counts any SQLITE_BUSY.
 */
function runWriter(): RoleResult {
  assertTmpIsolated(DB_PATH, FACTS_PATH);
  const db = openSeleneConnection(DB_PATH, FACTS_PATH); // read-write: WAL + busy_timeout + ATTACH
  let ops = 0;
  let busy = 0;
  const insert = db.prepare(
    `INSERT INTO facts.captured_notes
       (title, content, content_hash, tags, word_count, character_count, created_at, capture_type, test_run)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const deadline = Date.now() + DURATION_MS;
  while (Date.now() < deadline) {
    const content = `concurrency-writer note ${ops} @ ${Date.now()}`;
    const hash = createHash('sha256').update(content).digest('hex');
    try {
      insert.run(
        `t10-conc-${ops}`,
        content,
        hash,
        '[]',
        content.split(/\s+/).length,
        content.length,
        new Date().toISOString(),
        'dev-fixture',
        't10-concurrency'
      );
      ops += 1;
    } catch (err) {
      if (isBusy(err)) busy += 1;
      else throw err;
    }
  }
  db.close();
  return { role: 'writer', ops, busy };
}

/**
 * READER role (runs in the orchestrator, concurrent with the writer child): open the
 * two-file DB read-write and repeatedly (a) run getPendingNotes' exact query and (b) scan
 * raw_notes COUNT/GROUP — exactly the reads the pipeline does over the attached facts.
 */
function runReader(): RoleResult {
  assertTmpIsolated(DB_PATH, FACTS_PATH);
  const db = openSeleneConnection(DB_PATH, FACTS_PATH); // read-write conn: full WAL + busy_timeout
  let ops = 0;
  let busy = 0;
  // getPendingNotes' exact SQL (src/lib/db.ts) — kept inline to avoid the db.ts singleton.
  const pendingStmt = db.prepare(
    `SELECT * FROM raw_notes WHERE status = ? ORDER BY created_at ASC LIMIT ?`
  );
  const countStmt = db.prepare(`SELECT status, COUNT(*) AS n FROM raw_notes GROUP BY status`);
  const deadline = Date.now() + DURATION_MS;
  while (Date.now() < deadline) {
    try {
      pendingStmt.all('pending', 50); // the real pending read over the attached facts
      countStmt.all(); // full view scan
      ops += 1;
    } catch (err) {
      if (isBusy(err)) busy += 1;
      else throw err;
    }
  }
  db.close();
  return { role: 'reader', ops, busy };
}

function main(): void {
  if (process.argv.includes('--writer')) {
    const r = runWriter();
    process.stdout.write(JSON.stringify(r) + '\n'); // single-line JSON the parent parses
    return;
  }

  assertTmpIsolated(DB_PATH, FACTS_PATH);

  // Spawn the writer as a genuinely separate process (its own connection → real concurrency).
  const child = spawn('npx', ['ts-node', __filename, '--writer'], {
    env: process.env,
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  let childOut = '';
  child.stdout.on('data', (d: Buffer) => {
    childOut += d.toString();
  });

  // Run the reader loop in THIS process concurrently with the child writer.
  const reader = runReader();

  child.on('close', () => {
    let writer: RoleResult;
    try {
      writer = JSON.parse(childOut.trim().split('\n').pop() as string) as RoleResult;
    } catch {
      writer = { role: 'writer', ops: -1, busy: -1 };
    }
    const totalBusy = reader.busy + writer.busy;
    const totalOps = reader.ops + writer.ops;
    const result = {
      durationMs: DURATION_MS,
      reader: { ops: reader.ops, busy: reader.busy },
      writer: { ops: writer.ops, busy: writer.busy },
      totalOps,
      totalBusy,
      pass: totalBusy === 0 && writer.ops > 0 && reader.ops > 0,
    };
    process.stdout.write('CONCURRENCY_RESULT ' + JSON.stringify(result) + '\n');
    process.exit(result.pass ? 0 : 1);
  });
}

main();
