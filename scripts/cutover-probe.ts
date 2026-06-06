#!/usr/bin/env npx ts-node
/**
 * cutover-probe — the content-free Gate-1 capture→pending probe for scripts/cutover-prod.sh.
 *
 * After the cutover migration has converted a two-file (selene.db + facts.db) layout, this proves
 * the REAL capture write path still flows capture → 'pending' through the `raw_notes` view: it
 * inserts ONE note via the production `insertNote(note, conn)` (the SAME function the webhook uses),
 * asserts it reads back `status='pending'` (derivation-absence: no note_state row → the view
 * COALESCEs to 'pending'), then DELETES it from facts.captured_notes so NO test data survives.
 *
 * Content-free: it never selects a content-bearing column (only id + status). Prints PROBE PASS /
 * PROBE FAIL and exits non-zero on failure. gate1() invokes it with the cutover's
 * SELENE_DB_PATH / SELENE_FACTS_DB_PATH.
 *
 * SAFETY — two layers:
 *   1. Strictly /tmp-isolated: refuses unless BOTH SELENE_DB_PATH and SELENE_FACTS_DB_PATH are under
 *      /tmp (the same real-store guard the other fact-store probes use).
 *   2. The `src/lib/db` import is DEFERRED until AFTER that /tmp assertion. A top-level import would
 *      run db.ts's module-load side effects (ensureMigrated + open a long-lived connection on
 *      config.dbPath/factsDbPath) BEFORE any guard code — and config resolves those from
 *      SELENE_DB_PATH/SELENE_FACTS_DB_PATH, so a stray invocation without the /tmp override would
 *      auto-migrate the REAL dev DB. Importing only after the guard makes the probe safe by
 *      construction. openSeleneConnection pulls in db-config + facts-db only (NOT db.ts), so nothing
 *      evaluates db.ts before the guard.
 *
 * The caller also sets SELENE_VAULT_PATH=/tmp/cutover-probe-vault — belt-and-suspenders, since
 * insertNote never exports to a vault.
 */
import { createHash } from 'crypto';
import { openSeleneConnection, assertTmpIsolated } from '../src/lib/open-selene-connection';

const DB_PATH = process.env.SELENE_DB_PATH || '';
const FACTS_PATH = process.env.SELENE_FACTS_DB_PATH || '';
const TEST_RUN = 'cutover-probe';

async function main(): Promise<void> {
  // Refuse unless both DB paths are under /tmp (shared guard) — runs BEFORE the deferred db.ts
  // import below, so this probe only ever touches a /tmp copy.
  assertTmpIsolated(DB_PATH, FACTS_PATH);

  // Deferred import: db.ts's module-load side effects (ensureMigrated + long-lived connection on
  // config paths) run at THIS point, only AFTER the /tmp guard has passed. Fully typed — no `any`.
  const { insertNote } = await import('../src/lib/db');

  const marker = `${TEST_RUN}-${Date.now()}`;
  const content =
    `${marker}: a cutover gate-1 probe note about externalizing working memory with a visual ` +
    `checklist and reducing task-switching friction. Distinctive content so the capture path has ` +
    `a real, hashable body to write through facts.captured_notes.`;
  const note = {
    title: `${marker} cutover gate-1 capture probe`,
    content,
    contentHash: createHash('sha256').update(content).digest('hex'),
    tags: ['cutover', 'probe'],
    createdAt: new Date().toISOString(),
    testRun: TEST_RUN,
    captureType: 'cutover-probe',
  };

  // Read-write two-file open (WAL + busy_timeout + ATTACH facts + raw_notes TEMP view). This does
  // NOT load db.ts, so the deferred import above is the only thing that ever evaluates db.ts.
  const conn = openSeleneConnection(DB_PATH, FACTS_PATH);
  let ok = false;
  let id: number | undefined;
  let viewStatus: string | null = null;
  try {
    // The REAL production capture write path, against our /tmp connection.
    id = insertNote(note, conn);

    // Assert it reads back through the raw_notes view as 'pending' (no note_state row yet).
    const row = conn
      .prepare(`SELECT id, status FROM raw_notes WHERE id = ?`)
      .get(id) as { id: number; status: string } | undefined;
    viewStatus = row?.status ?? null;
    ok = row !== undefined && viewStatus === 'pending';
  } finally {
    // Clean up unconditionally — leave NO test data behind even if the assert threw. The fact lives
    // in the attached facts db; delete it there by test_run marker.
    conn.prepare(`DELETE FROM facts.captured_notes WHERE test_run = ?`).run(TEST_RUN);
    conn.close();
  }

  if (ok) {
    process.stdout.write(`PROBE PASS (id=${id} reads status='pending' via raw_notes view)\n`);
    process.exit(0);
  } else {
    process.stdout.write(
      `PROBE FAIL (id=${id ?? 'none'} viewStatus='${viewStatus ?? 'none'}', expected 'pending')\n`
    );
    process.exit(1);
  }
}

void main().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stderr.write(`PROBE FAIL (error): ${msg}\n`);
  process.exit(1);
});
