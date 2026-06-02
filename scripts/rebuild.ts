/**
 * rebuild — wipe selene.db, re-derive the whole corpus from facts.db, validate,
 * keep-or-rollback. Dev runs this directly; rebuild-prod.sh wraps it for prod.
 * Content-free (counts only). Flags: --dry-run, --json.
 *
 * Sequence: snapshot (PRE) → backup selene.db → wipe derived tables →
 * re-derive the pipeline (process-llm/distill-essences drained, then
 * synthesize-topics + export-obsidian once) → snapshot (POST) → verdict →
 * keep (prune old backups) OR rollback (restore the backup).
 *
 * Connections go through openSeleneConnection (NEVER db.ts — that opens a
 * singleton with import side effects).
 */
import { execFileSync } from 'child_process';
import { readdirSync, unlinkSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { config } from '../src/lib/config';
import { openSeleneConnection } from '../src/lib/open-selene-connection';
import {
  snapshot, wipe, verdict, thresholdsFromEnv, backupPath, pendingCount, drainDecision,
  vacuumBackup, restoreFromBackup, type Snapshot,
} from '../src/lib/rebuild-core';
import { logger } from '../src/lib/logger';

const DRY = process.argv.includes('--dry-run');
const JSON_OUT = process.argv.includes('--json');
const BACKUP_DIR = process.env.BACKUP_DIR ?? join(dirname(config.dbPath), 'backups');
// YYYYMMDDHHMMSS — 14 digits; slice(0,14) stops before the milliseconds '.' so the
// backup filename has no doubled dot. Env-pinnable so verify-rebuild.sh can assert it.
const STAMP = process.env.REBUILD_STAMP ?? new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);

function readSnapshot(): Snapshot {
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { readonly: true, fileMustExist: true });
  try {
    return snapshot(db);
  } finally {
    db.close();
  }
}

function backup(): string {
  const dest = backupPath(BACKUP_DIR, STAMP);
  // Dry-run touches nothing real: don't even create the backups/ dir.
  if (DRY) return dest;
  mkdirSync(BACKUP_DIR, { recursive: true });
  // VACUUM INTO (not copyFileSync): selene.db is WAL and the webhook server holds a
  // live handle during a prod rebuild. A file copy would miss uncheckpointed WAL
  // pages; VACUUM INTO writes a consistent main-schema snapshot (facts excluded).
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { fileMustExist: true });
  try {
    vacuumBackup(db, dest);
  } finally {
    db.close();
  }
  return dest;
}

function doWipe(): void {
  if (DRY) {
    logger.info('[dry-run] would truncate derived tables');
    return;
  }
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { fileMustExist: true });
  try {
    wipe(db);
  } finally {
    db.close();
  }
}

/** Outstanding re-derivation work (pending notes + essence-less processed rows).
 *  Delegates to rebuild-core.pendingCount, which routes both reads through the same
 *  absent-column-tolerant counter as snapshot() — so a never-distilled DB (no essence
 *  column yet) returns a count instead of throwing at the top of the drain loop.
 *  Monotonically decreasing across the loop, so it terminates; a stuck note still
 *  trips the no-progress break. */
function pendingWork(): number {
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { readonly: true });
  try {
    return pendingCount(db);
  } finally {
    db.close();
  }
}

const DRAIN_CAP = 1000; // defensive backstop; drainDecision owns real termination

function rederive(): void {
  const run = (wf: string): void => {
    if (DRY) {
      logger.info(`[dry-run] would run ${wf}`);
      return;
    }
    execFileSync('npx', ['ts-node', `src/workflows/${wf}.ts`], {
      stdio: 'inherit',
      env: { ...process.env, SELENE_ENV: config.env },
    });
  };
  // Dry-run logs the plan once per stage and drains nothing real.
  if (DRY) {
    for (const wf of ['process-llm', 'distill-essences', 'synthesize-topics', 'export-obsidian']) run(wf);
    return;
  }
  // Drain the two per-batch LLM stages until the (unit-tested) drainDecision says
  // stop — drained (work hit 0), stalled (a stuck note made no progress), or capped
  // (ceiling hit). The loop is intentionally unbounded: drainDecision guarantees
  // termination via DRAIN_CAP, so it's the single source of truth, not a second
  // bound here. Then run synthesis + export once over the full corpus.
  let previous = Infinity;
  for (let i = 0; ; i++) {
    const remaining = pendingWork();
    const decision = drainDecision(remaining, previous, i, DRAIN_CAP);
    if (decision !== 'continue') {
      if (decision !== 'drained') {
        logger.warn({ remaining, decision }, 'rebuild: drain stopped before zero — coverage gate will judge the shortfall');
      }
      break;
    }
    previous = remaining;
    run('process-llm');
    run('distill-essences');
  }
  run('synthesize-topics');
  run('export-obsidian');
}

/** Roll selene.db back to the pre-rebuild backup. This is the safety net for the
 *  whole feature, so it must never itself throw: a throw here would (a) escape the
 *  catch in main() as a bare stack trace and (b) risk a double-restore. Instead it
 *  swallows the failure and logs a loud MANUAL RECOVERY instruction — the operator
 *  can always copy the backup over by hand, and the disposable DB is rebuildable. */
function restore(backupFile: string): void {
  if (DRY) {
    logger.warn('[dry-run] would restore backup');
    return;
  }
  try {
    // Attach+row-copy restore (not a file copy over selene.db): the webhook server
    // holds a live WAL handle during a prod rebuild, so swapping the file underneath
    // it would corrupt that connection. restoreFromBackup writes through a connection.
    const db = openSeleneConnection(config.dbPath, config.factsDbPath, { fileMustExist: true });
    try {
      restoreFromBackup(db, backupFile);
    } finally {
      db.close();
    }
    logger.info({ backupFile }, 'rebuild: rolled back selene.db from backup');
  } catch (err) {
    logger.error(
      { err, backupFile, dbPath: config.dbPath },
      `rebuild: ROLLBACK FAILED — derived tables may be half-wiped. MANUAL RECOVERY: ` +
        `re-run rebuild, or restore rows from the backup at "${backupFile}"`,
    );
  }
}

function pruneBackups(): void {
  if (DRY) return;
  const files = readdirSync(BACKUP_DIR).filter((f) => f.startsWith('pre-rebuild-')).sort();
  for (const f of files.slice(0, Math.max(0, files.length - 5))) unlinkSync(join(BACKUP_DIR, f));
}

function main(): void {
  const t = thresholdsFromEnv();
  const pre = readSnapshot();
  logger.info({ pre }, 'rebuild: PRE snapshot');
  let backupFile = '';
  let wiped = false;
  try {
    // backup() is inside the try so a copy failure routes through the uniform abort
    // log below. It precedes the wipe, so wiped stays false and no restore fires.
    backupFile = backup();
    doWipe();
    wiped = true;
    // SIMULATE_REDERIVE_FAIL is placed AFTER the wipe (not before) so the verify
    // harness exercises the post-wipe rollback path — proving a crash mid-rebuild
    // self-heals by restoring the backup. Before the wipe it would be a no-op for
    // that test (the `if (wiped) restore` below would never fire).
    if (process.env.SIMULATE_REDERIVE_FAIL === '1') throw new Error('SIMULATE_REDERIVE_FAIL');
    rederive();
    let post = readSnapshot();
    if (process.env.SIMULATE_COVERAGE_FAIL === '1') post = { ...post, processed: 0 };
    if (process.env.SIMULATE_DRIFT_FAIL === '1') post = { ...post, clusters: 0 };
    const v = verdict(pre, post, t);
    const report = { pre, post, coverage: v.coverage, pass: v.pass, reasons: v.reasons, backup: backupFile };
    if (JSON_OUT) process.stdout.write(JSON.stringify(report, null, 2) + '\n');
    else logger.info(report, v.pass ? 'rebuild: PASS — keeping' : 'rebuild: FAIL — rolling back');
    // Dry-run is a rehearsal: nothing was wiped/re-derived, so POST==PRE makes the
    // gate verdict meaningless. Skip enforcement (no rollback, no exit 1) so callers
    // like rebuild-prod.sh can rehearse the full sequence under `set -e` without aborting.
    if (DRY) {
      logger.info('[dry-run] plan complete — verdict gate not enforced');
      return;
    }
    if (!v.pass) {
      restore(backupFile);
      process.exit(1);
    }
    pruneBackups();
  } catch (err) {
    logger.error({ err }, 'rebuild: aborted');
    if (wiped) restore(backupFile); // only restore if the wipe already happened
    process.exit(1);
  }
}

main();
