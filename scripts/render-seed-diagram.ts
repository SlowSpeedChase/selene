import { execSync } from 'child_process';
import { promises as fs } from 'fs';
import * as os from 'os';
import * as path from 'path';
import puppeteer from 'puppeteer';
import { extractAsciiBlock, buildSeedHtml } from '../src/lib/seed-diagram';

const INBOX = path.join(
  os.homedir(),
  'Library/Mobile Documents/com~apple~CloudDocs/Selene-Diagrams',
);
const SOURCE = 'docs/backend-block-diagrams.md';
const HEADING = process.argv[2] || 'System Architecture Overview';

async function main(): Promise<void> {
  // Standing rule: never seed from a stale picture.
  try {
    execSync('npx ts-node scripts/gen-system-map.ts --check', { stdio: 'ignore' });
  } catch {
    console.error('⚠️  SYSTEM-MAP.md is OUT OF DATE. Regenerate it and re-sync ' +
      'backend-block-diagrams.md before seeding. Aborting.');
    process.exit(1);
  }

  const md = await fs.readFile(SOURCE, 'utf8');
  const ascii = extractAsciiBlock(md, HEADING);
  const html = buildSeedHtml(ascii, `Selene — ${HEADING}`);

  await fs.mkdir(INBOX, { recursive: true });
  const out = path.join(INBOX, `seed-${HEADING.toLowerCase().replace(/[^a-z0-9]+/g, '-')}.png`);

  const browser = await puppeteer.launch();
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1600, height: 1200, deviceScaleFactor: 2 });
    await page.setContent(html, { waitUntil: 'load' });
    const el = await page.$('.wrap');
    if (!el) throw new Error('render target .wrap not found');
    await el.screenshot({ path: out });
  } finally {
    await browser.close();
  }
  console.log(`Seed written: ${out}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
