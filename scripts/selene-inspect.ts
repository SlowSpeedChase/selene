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
 * Targets config.dbPath (prod by default; SELENE_DB_PATH or SELENE_ENV repoints it).
 */
import Database from 'better-sqlite3';
import { config } from '../src/lib/config';
import { inspectSchema, inspectCounts, inspectCoverage } from '../src/lib/inspect';

function main(): void {
  const cmd = process.argv[2];
  const table = process.argv[3];

  if (!cmd || !['schema', 'counts', 'coverage'].includes(cmd)) {
    console.error('usage: selene-inspect <schema [table] | counts | coverage>');
    process.exit(2);
  }

  // Read-only: cannot write, and never opens the rw migration path in src/lib/db.ts.
  const db = new Database(config.dbPath, { readonly: true, fileMustExist: true });
  try {
    let report: unknown;
    if (cmd === 'schema') report = inspectSchema(db, table);
    else if (cmd === 'counts') report = inspectCounts(db);
    else report = inspectCoverage(db);

    console.log(JSON.stringify({ env: config.env, dbPath: config.dbPath, [cmd]: report }, null, 2));
  } finally {
    db.close();
  }
}

main();
