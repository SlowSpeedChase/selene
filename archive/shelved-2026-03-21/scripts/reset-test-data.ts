/**
 * Reset Test Data Script
 *
 * Full reset cycle for thread detection testing:
 * 1. Seed test notes
 * 2. Generate embeddings
 * 3. Compute associations
 *
 * Usage: npx ts-node scripts/reset-test-data.ts
 */

import { execSync } from 'child_process';
import * as path from 'path';

const ROOT_DIR = path.join(__dirname, '..');

function runCommand(description: string, command: string): void {
  console.log(`\n>>> ${description}`);
  console.log(`    ${command}\n`);

  try {
    execSync(command, {
      cwd: ROOT_DIR,
      stdio: 'inherit',
      env: { ...process.env, FORCE_COLOR: '1' },
    });
    console.log(`\n✓ ${description} complete`);
  } catch (err) {
    console.error(`\n✗ ${description} failed`);
    process.exit(1);
  }
}

function main(): void {
  console.log('=== Reset Test Data ===');
  console.log('This will seed test notes and regenerate embeddings/associations.\n');

  const startTime = Date.now();

  // Step 1: Seed test notes
  runCommand(
    'Seeding test notes',
    'npx ts-node scripts/seed-test-data.ts'
  );

  // Step 2: Generate embeddings
  runCommand(
    'Generating embeddings',
    'npx ts-node src/workflows/compute-embeddings.ts'
  );

  // Step 3: Compute associations
  runCommand(
    'Computing associations',
    'npx ts-node src/workflows/compute-associations.ts'
  );

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\n=== Reset Complete (${elapsed}s) ===`);
  console.log('\nNext steps:');
  console.log('  1. Run thread detection:');
  console.log('     npx ts-node src/workflows/detect-threads.ts 0.7');
  console.log('  2. Verify quality:');
  console.log('     npx ts-node scripts/verify-thread-quality.ts');
}

main();
