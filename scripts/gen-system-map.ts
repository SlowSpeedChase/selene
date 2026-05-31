// scripts/gen-system-map.ts
// Generates the workflow inventory table in docs/SYSTEM-MAP.md from source.
// Usage:  ts-node scripts/gen-system-map.ts            (write)
//         ts-node scripts/gen-system-map.ts --check    (exit 1 if out of date)
import * as fs from 'fs';
import * as path from 'path';
import {
  parseSchedule,
  parseMapComment,
  buildRow,
  renderWorkflowTable,
  injectGenerated,
  WorkflowRow,
} from '../src/lib/system-map';

const ROOT = path.resolve(__dirname, '..');
const WORKFLOWS_DIR = path.join(ROOT, 'src/workflows');
const LAUNCHD_DIR = path.join(ROOT, 'launchd');
const MAP_DOC = path.join(ROOT, 'docs/SYSTEM-MAP.md');

function buildRows(): WorkflowRow[] {
  const files = fs.readdirSync(WORKFLOWS_DIR).filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'));
  return files.map((f) => {
    const name = f.replace(/\.ts$/, '');
    const src = fs.readFileSync(path.join(WORKFLOWS_DIR, f), 'utf8');
    const meta = parseMapComment(src);
    const plistPath = path.join(LAUNCHD_DIR, `com.selene.${name}.plist`);
    const plistSchedule = fs.existsSync(plistPath) ? parseSchedule(fs.readFileSync(plistPath, 'utf8')) : null;
    return buildRow(name, meta, plistSchedule);
  });
}

function main(): void {
  const check = process.argv.includes('--check');
  const table = renderWorkflowTable(buildRows());
  const current = fs.readFileSync(MAP_DOC, 'utf8');
  const next = injectGenerated(current, table);
  if (check) {
    if (next !== current) {
      console.error('SYSTEM-MAP.md is OUT OF DATE. Run: npx ts-node scripts/gen-system-map.ts');
      process.exit(1);
    }
    console.log('SYSTEM-MAP.md is current.');
    return;
  }
  fs.writeFileSync(MAP_DOC, next);
  console.log(`SYSTEM-MAP.md updated (${buildRows().length} workflows).`);
}

main();
