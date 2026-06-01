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
 * CRITICAL — connection isolation: this module opens its OWN connection and imports ONLY the
 * PURE facts-db helpers. It deliberately does NOT import ./db: that module auto-ATTACHes facts
 * and runs an env-guard at module load, which would fire mid-surgery against a half-migrated DB.
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
 *
 * NOTE: the THIN CLI wrapper (resolves paths from env/config, logs, exits) lives in
 * `scripts/migrate-to-fact-store.ts` and imports `migrateToFactStore` from here. This file holds
 * only the pure migration library so `src/` modules (e.g. `ensure-migrated.ts`) can import it —
 * `tsconfig.json` (rootDir ./src) forbids a `src/` file importing from `scripts/`.
 */
import Database, { Database as DatabaseType } from 'better-sqlite3';
import {
  ensureFactsDbInitialized,
  attachFacts,
  ensureNoteStateTable,
} from './facts-db';

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

/**
 * The derived tables that (a) carry a `raw_note_id REFERENCES raw_notes(id)` FK AND (b) have a
 * LIVE writer in the current pipeline, so post-migration NEW notes get rows inserted. After the
 * `raw_notes` RENAME, SQLite (>=3.25, legacy_alter_table OFF) AUTO-REWRITES those FKs to point at
 * the FROZEN `raw_notes_legacy_backup`; with foreign_keys ON, inserting a row for an id only in
 * facts.captured_notes then throws SQLITE_CONSTRAINT_FOREIGNKEY. The split makes a SQL FK
 * structurally impossible (the referenced ids live cross-file in facts.captured_notes), so these
 * two tables must be rebuilt FK-free BEFORE the rename. The other 6 raw_notes-referencing tables
 * (processed_notes_apple, note_associations, thread_notes, thread_history, note_relationships,
 * sentiment_history) are DORMANT — no live writer — so their inert rewritten FK is never exercised
 * (foreign_key_check stays empty: all their EXISTING rows reference ids that ARE in the backup). We
 * deliberately leave them as-is. `note_state` was built FK-free from the start (facts-db.ts).
 */
const LIVE_FK_DERIVED_TABLES = ['processed_notes', 'note_embeddings'] as const;

/**
 * Remove ONLY the `raw_notes` foreign key from a CREATE TABLE statement, leaving every other
 * column, constraint (CHECK/UNIQUE/PK), and FK-to-other-tables intact. Pure + side-effect-free so
 * it can be unit-tested against the real DDL forms. Handles BOTH shapes the schema uses:
 *
 *   table-level:  `, FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) [ON DELETE ...] [ON UPDATE ...]`
 *                  → drop the whole clause AND its leading comma (so no dangling `,)` remains)
 *   inline column:`raw_note_id INTEGER REFERENCES raw_notes(id) [ON DELETE ...]`
 *                  → keep `raw_note_id INTEGER`, drop only the `REFERENCES raw_notes(...)` tail
 *
 * `[ON DELETE|UPDATE <action>]` actions can be one or two words (NO ACTION / SET NULL / SET DEFAULT
 * / CASCADE / RESTRICT). We never touch a FOREIGN KEY whose target table is NOT raw_notes.
 */
export function stripRawNotesFk(createSql: string): string {
  // Reusable fragments. `raw_notes\s*\(` anchors on the FK target's opening paren so we never
  // accidentally match a substring like `raw_notes_legacy_backup` (which has no `(` after it).
  const refClause =
    String.raw`REFERENCES\s+raw_notes\s*\([^)]*\)` + // REFERENCES raw_notes(id)
    String.raw`(?:\s+ON\s+DELETE\s+(?:NO\s+ACTION|SET\s+NULL|SET\s+DEFAULT|CASCADE|RESTRICT))?` +
    String.raw`(?:\s+ON\s+UPDATE\s+(?:NO\s+ACTION|SET\s+NULL|SET\s+DEFAULT|CASCADE|RESTRICT))?`;

  let out = createSql;

  // (1) Table-level: a leading comma, the FOREIGN KEY(...) clause, then the ref clause. Drop the
  // comma too. (?:CONSTRAINT name)? tolerates a named constraint.
  const tableLevel = new RegExp(
    String.raw`,\s*(?:CONSTRAINT\s+\S+\s+)?FOREIGN\s+KEY\s*\(\s*raw_note_id\s*\)\s*${refClause}`,
    'gi'
  );
  out = out.replace(tableLevel, '');

  // (2) Inline column form: a `REFERENCES raw_notes(...)` tail NOT introduced by FOREIGN KEY (those
  // were handled above). Strip just the tail, keeping the column + its type. Leading whitespace
  // before REFERENCES is consumed so `raw_note_id INTEGER REFERENCES …` → `raw_note_id INTEGER`.
  const inline = new RegExp(String.raw`\s+${refClause}`, 'gi');
  out = out.replace(inline, '');

  return out;
}

/**
 * Rebuild one derived table WITHOUT its raw_notes FK, preserving columns/types/PK and every other
 * constraint. Runs INSIDE the migration transaction, BEFORE the raw_notes RENAME (while the child
 * FK still cleanly references raw_notes). Idempotent-safe: only acts if the table exists.
 *
 * Strategy: read current `sql` from sqlite_master → strip the FK → CREATE `<t>__nofk` → copy all
 * rows → DROP `<t>` → RENAME `<t>__nofk` → `<t>`. Indexes are dropped with the old table, so they
 * are recreated from the captured CREATE INDEX statements. GUARDED: column names/types/pk and row
 * count must match the pre-rebuild snapshot, and the new sql must carry NO `raw_notes` reference —
 * any mismatch throws, rolling back the whole migration.
 */
function rebuildWithoutRawNotesFk(db: DatabaseType, table: string): void {
  if (!tableExists(db, table)) return;

  // Snapshot BEFORE: full column signature (cid order, name, type, pk) + row count, for the guard.
  type ColInfo = { cid: number; name: string; type: string; notnull: number; dflt_value: unknown; pk: number };
  const before = db.prepare(`PRAGMA table_info(${table})`).all() as ColInfo[];
  const beforeSig = before.map((c) => `${c.name}:${c.type}:${c.pk}`).join('|');
  const beforeCount = count(db, `SELECT COUNT(*) AS n FROM ${table}`);

  const createRow = db
    .prepare(`SELECT sql FROM sqlite_master WHERE type='table' AND name = ?`)
    .get(table) as { sql: string } | undefined;
  if (!createRow || !createRow.sql) {
    throw new Error(`FK strip: could not read CREATE sql for ${table}`);
  }

  // Capture the table's own indexes (the CREATE INDEX statements) so we can recreate them; DROP
  // TABLE removes them. Auto-indexes (sqlite_autoindex_*, from UNIQUE/PK) have a NULL sql and are
  // recreated automatically by the constraint in the rebuilt CREATE — skip those.
  const indexSqls = (
    db
      .prepare(`SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name = ? AND sql IS NOT NULL`)
      .all(table) as { sql: string }[]
  ).map((r) => r.sql);

  const newSql = stripRawNotesFk(createRow.sql);
  if (/raw_notes\s*\(/i.test(newSql)) {
    throw new Error(`FK strip: ${table} still references raw_notes after strip`);
  }
  // The rebuilt CREATE must target the temp name. Replace only the FIRST occurrence of the table
  // identifier right after CREATE TABLE (optionally IF NOT EXISTS / quoted), nothing else.
  const tmpName = `${table}__nofk`;
  const createHead = new RegExp(
    String.raw`^(\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?)(?:"${table}"|\`${table}\`|\[${table}\]|${table})`,
    'i'
  );
  if (!createHead.test(newSql)) {
    throw new Error(`FK strip: unexpected CREATE TABLE head for ${table}`);
  }
  const tmpCreate = newSql.replace(createHead, `$1${tmpName}`);

  db.exec(`DROP TABLE IF EXISTS ${tmpName}`);
  db.exec(tmpCreate);
  // Column-explicit copy (names from PRAGMA, never interpolated user data) — robust to column order.
  const colList = before.map((c) => c.name).join(', ');
  db.exec(`INSERT INTO ${tmpName} (${colList}) SELECT ${colList} FROM ${table}`);
  db.exec(`DROP TABLE ${table}`);
  db.exec(`ALTER TABLE ${tmpName} RENAME TO ${table}`);
  // Recreate the table's explicit indexes (they referenced the old table by name; that name is now
  // the rebuilt table, so the original CREATE INDEX text applies unchanged).
  for (const isql of indexSqls) db.exec(isql);

  // GUARD: signature + row count must match, and no raw_notes reference may remain.
  const after = db.prepare(`PRAGMA table_info(${table})`).all() as ColInfo[];
  const afterSig = after.map((c) => `${c.name}:${c.type}:${c.pk}`).join('|');
  if (afterSig !== beforeSig) {
    throw new Error(
      `FK strip guard failed for ${table}: column signature changed.\n  before: ${beforeSig}\n  after:  ${afterSig}`
    );
  }
  const afterCount = count(db, `SELECT COUNT(*) AS n FROM ${table}`);
  if (afterCount !== beforeCount) {
    throw new Error(`FK strip guard failed for ${table}: row count ${beforeCount} → ${afterCount}`);
  }
  const finalSql = (
    db.prepare(`SELECT sql FROM sqlite_master WHERE type='table' AND name = ?`).get(table) as {
      sql: string;
    }
  ).sql;
  if (/raw_notes/i.test(finalSql)) {
    throw new Error(`FK strip guard failed for ${table}: rebuilt DDL still mentions raw_notes`);
  }
}

function tableType(db: DatabaseType, name: string): string | undefined {
  const row = db.prepare(`SELECT type FROM sqlite_master WHERE name = ?`).get(name) as
    | { type: string }
    | undefined;
  return row?.type;
}

function tableExists(db: DatabaseType, name: string): boolean {
  return tableType(db, name) !== undefined;
}

/**
 * Does a table exist in the ATTACHED `facts` database? Reads `facts.sqlite_master` (the main
 * `sqlite_master` only sees `main`). Used by the incomplete-migration guard, which must treat a
 * missing `facts.captured_notes` as count 0 rather than letting an unqualified COUNT throw a raw
 * SQLite error that wouldn't carry our diagnostic message.
 */
function factsTableExists(db: DatabaseType, name: string): boolean {
  const row = db.prepare(`SELECT 1 AS x FROM facts.sqlite_master WHERE name = ?`).get(name) as
    | { x: number }
    | undefined;
  return row !== undefined;
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
    // (2) Idempotency guard. The durable on-disk marker is the legacy-backup table.
    //
    // (2a) backup EXISTS → a prior run already did the RENAME. But a crash could have committed
    // the RENAME without the facts inserts, leaving facts.captured_notes short/empty. Don't
    // blindly report success: compare the backup's row count to facts.captured_notes. Equal →
    // genuinely migrated (return alreadyMigrated). Different → INCOMPLETE migration: throw, do
    // NOT re-migrate (raw_notes is already gone) and do NOT silently no-op — the backup table is
    // the only copy of the data. We must attach facts to read its count; a missing
    // facts.captured_notes counts as 0 (factsTableExists guards the unqualified COUNT from
    // throwing a raw error that wouldn't carry our message).
    if (tableExists(db, 'raw_notes_legacy_backup')) {
      attachFacts(db, factsPath);
      const backupRows = count(db, `SELECT COUNT(*) AS n FROM raw_notes_legacy_backup`);
      const factRows = factsTableExists(db, 'captured_notes')
        ? count(db, `SELECT COUNT(*) AS n FROM facts.captured_notes`)
        : 0;
      if (backupRows !== factRows) {
        throw new Error(
          `Incomplete prior migration detected: raw_notes_legacy_backup has ${backupRows} rows ` +
            `but facts.captured_notes has ${factRows}. Manual recovery needed (the backup table ` +
            `holds your data).`
        );
      }
      return { notes: 0, reviewRows: 0, alreadyMigrated: true };
    }

    // (2b) No backup, but raw_notes is already a VIEW or absent → already in the two-file shape
    // (nothing to back up) → already-done, as before.
    const rawType = tableType(db, 'raw_notes');
    if (rawType === 'view' || rawType === undefined) {
      return { notes: 0, reviewRows: 0, alreadyMigrated: true };
    }

    // (3) Stand up facts.db (its own connection inits its schema), then attach it here and
    // ensure note_state in main. ATTACH happens BEFORE the transaction so the txn spans both.
    ensureFactsDbInitialized(factsPath);
    attachFacts(db, factsPath);

    // (3a) Cross-file atomic commit requires rollback-journal mode (WAL has no multi-DB
    // super-journal). This txn modifies BOTH selene.db and facts.db; under WAL a crash mid-commit
    // could leave them inconsistent. This is a one-shot offline migration touching the
    // source-of-truth, so prefer durability over speed. Set both files to DELETE journal mode
    // here — after attach, BEFORE the transaction (journal_mode can't change mid-transaction).
    // No explicit restore needed: the app reopens both files WAL on its next normal connection
    // via applyConnectionPragmas (db-config.ts sets journal_mode = WAL on every connection).
    db.pragma('journal_mode = DELETE');
    db.pragma('facts.journal_mode = DELETE');

    // (3b) We rebuild the live derived tables (processed_notes, note_embeddings) inside the txn to
    // strip their raw_notes FK. SQLite's DROP/CREATE table-rebuild trips foreign_key enforcement
    // unless FKs are OFF — and `PRAGMA foreign_keys` is a NO-OP inside a transaction, so it MUST be
    // toggled here, BEFORE db.transaction(...) runs. Restored in the `finally` below (the app's
    // next connection re-enables it anyway via applyConnectionPragmas). foreign_key_check after the
    // rename still validates integrity even with enforcement off.
    db.pragma('foreign_keys = OFF');

    // note_state is disposable bookkeeping, fully repopulated from raw_notes below. A stale one
    // (e.g. left by an earlier run with an older schema, missing a column) must be replaced, not
    // merged — CREATE IF NOT EXISTS would keep the wrong shape.
    db.exec('DROP TABLE IF EXISTS note_state');
    ensureNoteStateTable(db);

    const hasProcessedNotes = tableExists(db, 'processed_notes');
    const hasPkmReviewState = tableExists(db, 'pkm_review_state');

    // note_state columns = allowlist ∩ columns actually present on raw_notes.
    const rawCols = columnsOf(db, 'raw_notes');
    const presentBookkeeping = BOOKKEEPING_COLUMNS.filter((c) => rawCols.has(c));

    // PRE-EXISTING referential cruft (orphaned processed_notes, dangling source_note_id self-refs)
    // is SOURCE data — real prod accumulates it through historical deletions. A FAITHFUL migration
    // copies every note id-preservingly, so it can neither create nor remove these; the relationship
    // is INVARIANT. Capture the counts now (raw_notes still intact, pre-txn) and assert post == pre
    // below — which TOLERATES existing cruft while still catching a migration that drops/remaps ids.
    const preProcOrphans = hasProcessedNotes
      ? count(db, `SELECT COUNT(*) AS n FROM processed_notes WHERE raw_note_id NOT IN (SELECT id FROM raw_notes)`)
      : 0;
    const preDanglingSelfRefs = rawCols.has('source_note_id')
      ? count(
          db,
          `SELECT COUNT(*) AS n FROM raw_notes WHERE source_note_id IS NOT NULL AND source_note_id NOT IN (SELECT id FROM raw_notes)`
        )
      : 0;
    // Whole-DB FK violations present in the SOURCE (against the original schema, pre-strip/rename).
    // The migration only REMOVES the raw_notes FK from live tables and faithfully copies data, so it
    // can never INCREASE violations — every post-migration violation is either one of these
    // pre-existing ones (a dormant/self FK now pointing at raw_notes_legacy_backup) or a real bug.
    const preFkViolations = (db.pragma('foreign_key_check') as unknown[]).length;

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

      // (4c2) Strip the raw_notes FK from the LIVE derived tables BEFORE the rename. If we
      // renamed first, SQLite would auto-rewrite their FK to point at raw_notes_legacy_backup
      // (frozen id set), and every post-migration NEW note (only in facts.captured_notes) would
      // fail the FK on insert — killing process-llm for all future captures. Each rebuild is
      // guarded (column signature + row count + no-raw_notes-ref); any failure throws → rollback.
      for (const t of LIVE_FK_DERIVED_TABLES) {
        rebuildWithoutRawNotesFk(db, t);
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
        // post != pre means the migration CHANGED the note id-set (dropped/remapped a raw_note),
        // turning a previously-valid processed_notes row into an orphan — a real bug → rollback.
        // post == pre (incl. pre-existing orphans) is a faithful migration → tolerate.
        if (procOrphans !== preProcOrphans) {
          throw new Error(
            `migration assert failed: processed_notes orphans changed ${preProcOrphans} → ${procOrphans} (migration altered the note id-set)`
          );
        }
        if (procOrphans > 0) {
          // eslint-disable-next-line no-console
          console.log(`note: preserved ${procOrphans} pre-existing orphaned processed_notes row(s) (raw_note_id with no surviving note)`);
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
      // Same invariant as processed_notes orphans: a self-ref to a since-deleted note is pre-existing
      // SOURCE cruft the migration preserves verbatim. Only a CHANGE (post != pre) signals a bug.
      if (danglingSelfRefs !== preDanglingSelfRefs) {
        throw new Error(
          `migration assert failed: dangling source_note_id self-refs changed ${preDanglingSelfRefs} → ${danglingSelfRefs} (migration altered the note id-set)`
        );
      }
      if (danglingSelfRefs > 0) {
        // eslint-disable-next-line no-console
        console.log(`note: preserved ${danglingSelfRefs} pre-existing dangling source_note_id self-ref(s) (annotation of a since-deleted note)`);
      }

      // (4g) Whole-DB FK integrity assert. `PRAGMA foreign_key_check` returns one row per broken
      // FK reference (table, rowid, referenced-table, fkid) and RUNS even with enforcement OFF.
      // This proves two things at once: the rebuilt live tables no longer carry a raw_notes FK,
      // AND the dormant tables' EXISTING rows still satisfy their (now legacy_backup-pointed) FKs
      // — i.e. leaving them is genuinely safe. Any row here → throw → rollback the whole migration.
      const fkViolations = db.pragma('foreign_key_check') as Array<{
        table: string;
        rowid: number;
        parent: string;
        fkid: number;
      }>;
      // post > pre means the migration INTRODUCED a violation (a bug) → rollback. post <= pre means
      // every remaining violation was already in the source (pre-existing cruft now pointing at
      // raw_notes_legacy_backup) — faithful, so tolerate. The live-tables-are-FK-free guarantee is
      // separately enforced by rebuildWithoutRawNotesFk's own checks, not by this assert.
      if (fkViolations.length > preFkViolations) {
        const detail = fkViolations
          .map((v) => `${v.table} rowid=${v.rowid} -> ${v.parent} (fkid=${v.fkid})`)
          .join('; ');
        throw new Error(
          `migration assert failed: foreign_key_check violations grew ${preFkViolations} → ${fkViolations.length} (migration introduced a broken reference): ${detail}`
        );
      }
      if (fkViolations.length > 0) {
        // eslint-disable-next-line no-console
        console.log(`note: ${fkViolations.length} pre-existing FK violation(s) preserved against raw_notes_legacy_backup (dormant/self refs to since-deleted notes)`);
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
