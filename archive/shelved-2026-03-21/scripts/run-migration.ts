/**
 * Run SQL migration files against the database
 */

import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { db } from '../src/lib';

const migrationsDir = join(__dirname, '../database/migrations');

function runMigrations() {
  console.log('=== Running Migrations ===\n');

  const files = readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    console.log(`Running: ${file}`);
    const sql = readFileSync(join(migrationsDir, file), 'utf-8');

    try {
      db.exec(sql);
      console.log(`  OK\n`);
    } catch (err) {
      const error = err as Error;
      // Check if it's a "table already exists" error (safe to ignore)
      if (error.message.includes('already exists')) {
        console.log(`  SKIPPED (already exists)\n`);
      } else {
        console.error(`  FAILED: ${error.message}\n`);
        // Continue with other migrations
      }
    }
  }

  console.log('=== Migrations Complete ===');
}

runMigrations();
