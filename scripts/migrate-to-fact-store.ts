/**
 * Task 8b — THE MIGRATION (thin CLI wrapper).
 *
 * The migration library now lives in `src/lib/migrate-to-fact-store.ts` (so `src/` modules — e.g.
 * the `ensure-migrated` startup guard — can import it; `tsconfig.json` rootDir `./src` forbids a
 * `src/` file importing from `scripts/`). This file keeps ONLY the CLI entrypoint: resolve the DB
 * paths (env override → config default), call `migrateToFactStore`, log, exit.
 */
import { config } from '../src/lib/config';
import { migrateToFactStore } from '../src/lib/migrate-to-fact-store';

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
