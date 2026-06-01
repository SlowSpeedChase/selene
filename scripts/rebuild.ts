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
import { copyFileSync, readdirSync, unlinkSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { config } from '../src/lib/config';
import { openSeleneConnection } from '../src/lib/open-selene-connection';
import { snapshot, wipe, verdict, thresholdsFromEnv, backupPath, type Snapshot } from '../src/lib/rebuild-core';
import { logger } from '../src/lib/logger';

const DRY = process.argv.includes('--dry-run');
const JSON_OUT = process.argv.includes('--json');
const BACKUP_DIR = process.env.BACKUP_DIR ?? join(dirname(config.dbPath), 'backups');
const STAMP = process.env.REBUILD_STAMP ?? new Date().toISOString().replace(/[-:T]/g, '').slice(0, 15);

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
  copyFileSync(config.dbPath, dest);
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

/** Outstanding re-derivation work: notes awaiting LLM extraction + processed notes
 *  still missing an essence. Mirrors dev-process-batch.sh, which drains both stages
 *  to zero separately — gating on the COMBINED total keeps the loop correct even if
 *  one stage's batch outpaces the other (the snippet's pending-only gate could run
 *  synth/export over under-distilled essences). Monotonically decreasing, so it
 *  terminates; a stuck note still trips the no-progress break. */
function pendingWork(): number {
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { readonly: true });
  try {
    const pending = (db.prepare(`SELECT COUNT(*) n FROM raw_notes WHERE status='pending'`).get() as { n: number }).n;
    const noEssence = (db.prepare(`SELECT COUNT(*) n FROM processed_notes WHERE essence IS NULL`).get() as { n: number }).n;
    return pending + noEssence;
  } finally {
    db.close();
  }
}

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
  let last = -1;
  for (let i = 0; i < 1000; i++) {
    if (!DRY && pendingWork() === 0) break;
    run('process-llm');
    run('distill-essences');
    if (DRY) break;
    const now = pendingWork();
    if (now === last) break; // no progress — a stuck note would otherwise spin forever
    last = now;
  }
  run('synthesize-topics');
  run('export-obsidian');
}

function restore(backupFile: string): void {
  if (DRY) {
    logger.warn('[dry-run] would restore backup');
    return;
  }
  copyFileSync(backupFile, config.dbPath);
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
  const backupFile = backup();
  let wiped = false;
  try {
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
