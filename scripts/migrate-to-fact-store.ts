/**
 * Task 8b — THE MIGRATION: convert an EXISTING single-file selene.db into the two-file
 * fact-store layout, in ONE all-or-nothing transaction, idempotently, preserving ids.
 *
 * The split: `facts.db` (precious) owns `captured_notes` + `review_state`; `selene.db`
 * (disposable) owns the derived tables + a `note_state` bookkeeping table and ATTACHes
 * facts.db AS `facts`. `raw_notes` stops being a physical table — it becomes a per-connection
 * TEMP VIEW (facts.captured_notes LEFT JOIN note_state) materialized at runtime by db.ts /
 * test connections via `ensureRawNotesView`. THIS migration does NOT create the view; it
 * renames the physical table to `raw_notes_legacy_backup` and copies its data into the new
 * homes.
 *
 * CRITICAL — connection isolation: this script opens its OWN connection and imports ONLY the
 * PURE facts-db helpers + `config` (paths). It deliberately does NOT import ../src/lib/db:
 * that module auto-ATTACHes facts and runs an env-guard at module load, which would fire
 * mid-surgery against a half-migrated DB. Importing `config` is safe — it opens no connection.
 *
 * CRITICAL — id preservation: every copy names `id` EXPLICITLY
 * (`INSERT INTO facts.captured_notes (id, …) SELECT id, … FROM raw_notes`). A fresh
 * AUTOINCREMENT copy would silently dangle every raw_note_id / source_note_id reference in the
 * derived tables. A post-commit `facts.sqlite_sequence` assert proves AUTOINCREMENT continues
 * past the largest migrated id so fresh inserts can never collide.
 *
 * CRITICAL — schema qualification: `captured_notes`, `review_state`, and THEIR
 * `sqlite_sequence` live in facts.db → always `facts.`-qualified. `raw_notes`,
 * `raw_notes_legacy_backup`, `note_state`, `processed_notes`, `pkm_review_state` live in the
 * main selene.db → unqualified.
 */
import Database, { Database as DatabaseType } from 'better-sqlite3';
import { config } from '../src/lib/config';
import {
  ensureFactsDbInitialized,
  attachFacts,
  ensureNoteStateTable,
} from '../src/lib/facts-db';

/** The 15 immutable note FACTS — copied to facts.captured_notes, id EXPLICIT. */
const FACT_COLUMNS = [
  'id', 'title', 'content', 'content_hash', 'source_type', 'word_count', 'character_count',
  'tags', 'created_at', 'imported_at', 'source_uuid', 'calendar_event', 'capture_type',
  'source_note_id', 'test_run',
] as const;

/**
 * The 7 derivable bookkeeping columns that move to note_state. Some were added by import-time
 * ALTERs and may be absent on a given DB — we intersect this allowlist with the columns
 * actually present on raw_notes and copy only those. The identifiers interpolated into SQL
 * come from THIS hardcoded allowlist, never from raw PRAGMA output.
 */
const BOOKKEEPING_COLUMNS = [
  'status', 'processed_at', 'exported_at', 'exported_to_obsidian', 'obsidian_export_hash',
  'status_folio', 'inbox_status',
] as const;

function tableType(db: DatabaseType, name: string): string | undefined {
  const row = db.prepare(`SELECT type FROM sqlite_master WHERE name = ?`).get(name) as
    | { type: string }
    | undefined;
  return row?.type;
}

function tableExists(db: DatabaseType, name: string): boolean {
  return tableType(db, name) !== undefined;
}

function columnsOf(db: DatabaseType, table: string): Set<string> {
  const rows = db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
  return new Set(rows.map((r) => r.name));
}

function count(db: DatabaseType, sql: string): number {
  return (db.prepare(sql).get() as { n: number }).n;
}

/**
 * Migrate a single-file selene.db at `dbPath` into the two-file layout (selene.db + facts.db
 * at `factsPath`). Returns the number of notes + review rows moved, or `{alreadyMigrated:true}`
 * if the DB is already in the two-file shape. Idempotent and transactional.
 */
export function migrateToFactStore(
  dbPath: string,
  factsPath: string
): { notes: number; reviewRows: number; alreadyMigrated: boolean } {
  const db = new Database(dbPath);
  try {
    // (2) Idempotency guard. The durable on-disk marker is the legacy-backup table; we also
    // treat "raw_notes is already a VIEW" or "raw_notes absent" as already-done.
    const rawType = tableType(db, 'raw_notes');
    if (rawType === 'view' || tableExists(db, 'raw_notes_legacy_backup') || rawType === undefined) {
      return { notes: 0, reviewRows: 0, alreadyMigrated: true };
    }

    // (3) Stand up facts.db (its own connection inits its schema), then attach it here and
    // ensure note_state in main. ATTACH happens BEFORE the transaction so the txn spans both.
    ensureFactsDbInitialized(factsPath);
    attachFacts(db, factsPath);
    ensureNoteStateTable(db);

    const hasProcessedNotes = tableExists(db, 'processed_notes');
    const hasPkmReviewState = tableExists(db, 'pkm_review_state');

    // note_state columns = allowlist ∩ columns actually present on raw_notes.
    const rawCols = columnsOf(db, 'raw_notes');
    const presentBookkeeping = BOOKKEEPING_COLUMNS.filter((c) => rawCols.has(c));

    const txn = db.transaction(() => {
      // (4a) Copy the 15 facts, id EXPLICIT — preserves ids so derived references stay valid.
      const factCols = FACT_COLUMNS.join(', ');
      db.exec(
        `INSERT INTO facts.captured_notes (${factCols}) SELECT ${factCols} FROM raw_notes`
      );

      // (4b) Copy present bookkeeping into note_state, keyed by the real id. Every row gets a
      // note_state row carrying its true current status (faithful). Post-migration NEW notes
      // get no note_state row → the view COALESCEs status/inbox_status to 'pending'.
      const stateInsertCols = ['raw_note_id', ...presentBookkeeping].join(', ');
      const stateSelectCols = ['id', ...presentBookkeeping].join(', ');
      db.exec(
        `INSERT INTO note_state (${stateInsertCols}) SELECT ${stateSelectCols} FROM raw_notes`
      );

      // (4c) Migrate human review flags, if the legacy table exists.
      let reviewRows = 0;
      if (hasPkmReviewState) {
        db.exec(
          `INSERT INTO facts.review_state (entity_type, entity_id, last_surfaced_at, surface_count)
           SELECT entity_type, entity_id, last_surfaced_at, surface_count FROM pkm_review_state`
        );
        reviewRows = count(db, `SELECT COUNT(*) AS n FROM facts.review_state`);
      }

      // (4d) Retire the physical table (kept as a backup, NOT dropped). The view is created
      // per-connection at runtime — not here.
      db.exec(`ALTER TABLE raw_notes RENAME TO raw_notes_legacy_backup`);

      // (4e) Referential-integrity asserts — any failure ROLLS BACK the whole txn.
      const movedNotes = count(db, `SELECT COUNT(*) AS n FROM facts.captured_notes`);
      const backupNotes = count(db, `SELECT COUNT(*) AS n FROM raw_notes_legacy_backup`);
      if (movedNotes !== backupNotes) {
        throw new Error(
          `migration assert failed: captured_notes (${movedNotes}) != raw_notes_legacy_backup (${backupNotes})`
        );
      }
      if (hasProcessedNotes) {
        const procOrphans = count(
          db,
          `SELECT COUNT(*) AS n FROM processed_notes WHERE raw_note_id NOT IN (SELECT id FROM facts.captured_notes)`
        );
        if (procOrphans !== 0) {
          throw new Error(`migration assert failed: ${procOrphans} processed_notes orphan(s)`);
        }
      }
      const stateOrphans = count(
        db,
        `SELECT COUNT(*) AS n FROM note_state WHERE raw_note_id NOT IN (SELECT id FROM facts.captured_notes)`
      );
      if (stateOrphans !== 0) {
        throw new Error(`migration assert failed: ${stateOrphans} note_state orphan(s)`);
      }
      const danglingSelfRefs = count(
        db,
        `SELECT COUNT(*) AS n FROM facts.captured_notes
         WHERE source_note_id IS NOT NULL
           AND source_note_id NOT IN (SELECT id FROM facts.captured_notes)`
      );
      if (danglingSelfRefs !== 0) {
        throw new Error(`migration assert failed: ${danglingSelfRefs} dangling source_note_id self-ref(s)`);
      }

      return { notes: movedNotes, reviewRows };
    });

    // (4f) Commit (or, on any thrown assert, better-sqlite3 ROLLBACKs and rethrows).
    const { notes, reviewRows } = txn();

    // (5) Post-commit sqlite_sequence assert — proves AUTOINCREMENT continues past the largest
    // migrated id (fresh inserts can't collide). captured_notes lives in facts.db, so its
    // sqlite_sequence is facts.sqlite_sequence. Skip on an empty source (no row yet).
    const seqRow = db
      .prepare(`SELECT seq FROM facts.sqlite_sequence WHERE name = 'captured_notes'`)
      .get() as { seq: number } | undefined;
    if (seqRow !== undefined) {
      const maxId = (
        db.prepare(`SELECT MAX(id) AS m FROM facts.captured_notes`).get() as { m: number | null }
      ).m;
      if (maxId !== null && seqRow.seq < maxId) {
        throw new Error(
          `migration assert failed: facts.sqlite_sequence(captured_notes)=${seqRow.seq} < MAX(id)=${maxId}`
        );
      }
    }

    return { notes, reviewRows, alreadyMigrated: false };
  } finally {
    db.close();
  }
}

/** Thin CLI wrapper: resolve paths (env override → config default) and run. */
function main(): void {
  const dbPath = process.env.SELENE_DB_PATH || config.dbPath;
  const factsPath = process.env.SELENE_FACTS_DB_PATH || config.factsDbPath;

  const result = migrateToFactStore(dbPath, factsPath);
  if (result.alreadyMigrated) {
    // eslint-disable-next-line no-console
    console.log(`already migrated, no-op (db=${dbPath})`);
    return;
  }
  // eslint-disable-next-line no-console
  console.log(
    `migrated ${result.notes} note(s) → ${factsPath} (review_state rows: ${result.reviewRows}); ` +
      `raw_notes renamed to raw_notes_legacy_backup in ${dbPath}`
  );
}

if (require.main === module) {
  main();
}
