#!/usr/bin/env npx ts-node
import { readFileSync } from 'fs';
import { anonymize } from '../src/lib/anonymize';

const source = process.argv[2];

if (!source) {
  console.error('Usage: npx ts-node scripts/anonymize-debug.ts <file-or-stdin>');
  console.error('  npx ts-node scripts/anonymize-debug.ts myfile.txt');
  console.error('  echo "text" | npx ts-node scripts/anonymize-debug.ts -');
  process.exit(1);
}

const raw = source === '-'
  ? readFileSync('/dev/stdin', 'utf-8')
  : readFileSync(source, 'utf-8');

const { text, tokenMap } = anonymize(raw);

console.log('=== ANONYMIZED OUTPUT (safe to share) ===\n');
console.log(text);
console.log('\n=== TOKEN MAP (keep local, do not share) ===');
for (const [token, value] of Object.entries(tokenMap)) {
  console.log(`  ${token} → ${value}`);
}
