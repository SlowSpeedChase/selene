#!/usr/bin/env npx ts-node
/**
 * selene-inspect — the ONLY sanctioned way for Claude to look at the prod DB.
 *
 * Opens a READ-ONLY connection and prints schema / counts / coverage. By construction it
 * never selects a content-bearing column, so no real note text reaches Claude's context.
 * The prod-data-guard hook allowlists this script for exactly that reason.
 *
 *   npx ts-node scripts/selene-inspect.ts schema [table]
 *   npx ts-node scripts/selene-inspect.ts counts
 *   npx ts-node scripts/selene-inspect.ts coverage
 *
 * Targets config.dbPath/config.factsDbPath (prod by default; SELENE_DB_PATH / SELENE_FACTS_DB_PATH
 * or SELENE_ENV repoint them).
 *
 * Fact-store split: the note facts now live in facts.captured_notes, and `raw_notes` is a
 * per-connection TEMP VIEW (facts.captured_notes LEFT JOIN note_state). We open the two-file layout
 * READONLY via openSeleneConnection — it ATTACHes facts.db readonly and materializes the temp view,
 * so the inspector reads `raw_notes` exactly as the live app does, without writing the precious
 * facts file. (A readonly main makes the attached facts file readonly too, so this can't mutate it.)
 */
import { config } from '../src/lib/config';
import { openSeleneConnection } from '../src/lib/open-selene-connection';
import { inspectSchema, inspectCounts, inspectCoverage } from '../src/lib/inspect';

function main(): void {
  const cmd = process.argv[2];
  const table = process.argv[3];

  if (!cmd || !['schema', 'counts', 'coverage'].includes(cmd)) {
    console.error('usage: selene-inspect <schema [table] | counts | coverage>');
    process.exit(2);
  }

  // Read-only two-file open: cannot write either file, and never runs the rw migration path in
  // src/lib/db.ts. facts.db must already exist (a readonly open never creates it).
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, {
    readonly: true,
    fileMustExist: true,
  });
  try {
    let report: unknown;
    if (cmd === 'schema') report = inspectSchema(db, table);
    else if (cmd === 'counts') report = inspectCounts(db);
    else report = inspectCoverage(db);

    console.log(
      JSON.stringify(
        { env: config.env, dbPath: config.dbPath, factsDbPath: config.factsDbPath, [cmd]: report },
        null,
        2
      )
    );
  } finally {
    db.close();
  }
}

main();
